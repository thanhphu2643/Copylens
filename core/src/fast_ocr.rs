//! PP-OCRv5 on ONNX Runtime's CPU provider. Loading takes a fraction of a second and
//! never goes through Apple's model compiler, which makes this the fallback when
//! Vision stalls. Latin text only: the model has no Vietnamese tone marks.

use crate::{layout, Fragment};
use ort::session::Session;
use ort::value::Tensor;

static DETECTOR: &[u8] = include_bytes!("../models/det.onnx");
static RECOGNIZER: &[u8] = include_bytes!("../models/rec.onnx");
static DICTIONARY: &str = include_str!("../models/dict.txt");

/// Longest detector input side. Captures are at least 2x, so this keeps small text legible.
const MAX_DETECTOR_SIDE: f32 = 1920.0;
const TEXT_PIXEL_THRESHOLD: f32 = 0.3;
const MIN_BOX_SCORE: f32 = 0.5;
const UNCLIP_RATIO: f32 = 1.6;
const LINE_HEIGHT: usize = 48;
const BATCH_SIZE: usize = 16;
const MIN_TEXT_SCORE: f32 = 0.5;

pub struct Image<'a> {
    /// RGBA, `stride` bytes per row.
    pub pixels: &'a [u8],
    pub width: usize,
    pub height: usize,
    pub stride: usize,
}

#[derive(Clone, Copy)]
struct Rect {
    left: f32,
    top: f32,
    right: f32,
    bottom: f32,
}

pub fn recognize(image: &Image) -> Result<String, Box<dyn std::error::Error>> {
    let environment = ort::init_from(runtime_path())?.build()?;
    let mut detector = Session::builder(&environment)?.commit_from_memory(DETECTOR)?;
    let boxes = detect(&mut detector, image)?;
    drop(detector);
    if boxes.is_empty() {
        return Ok(String::new());
    }
    let mut recognizer = Session::builder(&environment)?.commit_from_memory(RECOGNIZER)?;
    let fragments = read_lines(&mut recognizer, image, boxes)?;
    Ok(layout(fragments))
}

/// The official runtime that `build.sh` puts in the app bundle. `cargo test` points
/// `ORT_DYLIB_PATH` at the downloaded copy instead.
fn runtime_path() -> std::path::PathBuf {
    std::env::var_os("ORT_DYLIB_PATH").map(Into::into).unwrap_or_else(|| {
        let executable = std::env::current_exe().unwrap_or_default();
        executable.with_file_name("../Frameworks/libonnxruntime.dylib")
    })
}

/// Writes the normalized BGR planes of `source` into a `width`x`height` CHW buffer.
#[allow(clippy::too_many_arguments)]
fn write_planes(
    image: &Image,
    source: Rect,
    width: usize,
    height: usize,
    mean: [f32; 3],
    std: [f32; 3],
    out: &mut [f32],
    out_width: usize,
) {
    let sx = (source.right - source.left) / width as f32;
    let sy = (source.bottom - source.top) / height as f32;
    let plane = out_width * height;
    for y in 0..height {
        let fy = (source.top + (y as f32 + 0.5) * sy - 0.5).clamp(0.0, image.height as f32 - 1.0);
        let y0 = fy as usize;
        let y1 = (y0 + 1).min(image.height - 1);
        let wy = fy - y0 as f32;
        let (row0, row1) = (y0 * image.stride, y1 * image.stride);
        for x in 0..width {
            let fx = (source.left + (x as f32 + 0.5) * sx - 0.5).clamp(0.0, image.width as f32 - 1.0);
            let x0 = fx as usize;
            let x1 = (x0 + 1).min(image.width - 1);
            let wx = fx - x0 as f32;
            for (channel, rgba_offset) in [2usize, 1, 0].into_iter().enumerate() {
                let at = |row: usize, column: usize| image.pixels[row + column * 4 + rgba_offset] as f32;
                let top = at(row0, x0) * (1.0 - wx) + at(row0, x1) * wx;
                let bottom = at(row1, x0) * (1.0 - wx) + at(row1, x1) * wx;
                let value = (top * (1.0 - wy) + bottom * wy) / 255.0;
                out[channel * plane + y * out_width + x] = (value - mean[channel]) / std[channel];
            }
        }
    }
}

fn detect(session: &mut Session, image: &Image) -> ort::Result<Vec<Rect>> {
    let longest = image.width.max(image.height) as f32;
    let scale = (MAX_DETECTOR_SIDE / longest).min(1.0);
    let round = |side: usize| (((side as f32 * scale / 32.0).round() as usize).max(1)) * 32;
    let (width, height) = (round(image.width), round(image.height));

    let mut input = vec![0f32; 3 * width * height];
    let whole = Rect { left: 0.0, top: 0.0, right: image.width as f32, bottom: image.height as f32 };
    write_planes(image, whole, width, height, [0.485, 0.456, 0.406], [0.229, 0.224, 0.225], &mut input, width);

    let tensor = Tensor::from_array(([1usize, 3, height, width], input))?;
    let outputs = session.run(ort::inputs![tensor])?;
    let (_, probability) = outputs[0].try_extract_tensor::<f32>()?;

    let (scale_x, scale_y) = (image.width as f32 / width as f32, image.height as f32 / height as f32);
    let boxes = text_regions(probability, width, height)
        .into_iter()
        .map(|region| Rect {
            left: (region.left * scale_x).max(0.0),
            top: (region.top * scale_y).max(0.0),
            right: (region.right * scale_x).min(image.width as f32),
            bottom: (region.bottom * scale_y).min(image.height as f32),
        })
        .filter(|rect| rect.right - rect.left >= 2.0 && rect.bottom - rect.top >= 2.0)
        .collect();
    Ok(boxes)
}

/// DB post-processing: connected components of the probability map, expanded back to
/// full text height because the model predicts a shrunken core of each line.
fn text_regions(probability: &[f32], width: usize, height: usize) -> Vec<Rect> {
    let mut visited = vec![false; width * height];
    let mut stack = Vec::new();
    let mut regions = Vec::new();
    for start in 0..width * height {
        if visited[start] || probability[start] < TEXT_PIXEL_THRESHOLD {
            continue;
        }
        visited[start] = true;
        stack.push(start);
        let (mut left, mut right, mut top, mut bottom) = (width, 0, height, 0);
        let (mut sum, mut count) = (0f32, 0usize);
        while let Some(index) = stack.pop() {
            let (x, y) = (index % width, index / width);
            left = left.min(x);
            right = right.max(x);
            top = top.min(y);
            bottom = bottom.max(y);
            sum += probability[index];
            count += 1;
            let mut visit = |next: usize| {
                if !visited[next] && probability[next] >= TEXT_PIXEL_THRESHOLD {
                    visited[next] = true;
                    stack.push(next);
                }
            };
            if x > 0 { visit(index - 1) }
            if x + 1 < width { visit(index + 1) }
            if y > 0 { visit(index - width) }
            if y + 1 < height { visit(index + width) }
        }
        if count < 4 || sum / (count as f32) < MIN_BOX_SCORE {
            continue;
        }
        let (w, h) = ((right - left + 1) as f32, (bottom - top + 1) as f32);
        let offset = w * h * UNCLIP_RATIO / (2.0 * (w + h));
        regions.push(Rect {
            left: left as f32 - offset,
            top: top as f32 - offset,
            right: right as f32 + 1.0 + offset,
            bottom: bottom as f32 + 1.0 + offset,
        });
    }
    regions
}

fn read_lines(session: &mut Session, image: &Image, mut boxes: Vec<Rect>) -> ort::Result<Vec<Fragment>> {
    let dictionary: Vec<&str> = DICTIONARY.lines().collect();
    // Similar widths batch together, so less time goes into padding.
    boxes.sort_by(|a, b| aspect(a).total_cmp(&aspect(b)));

    let mut fragments = Vec::with_capacity(boxes.len());
    for batch in boxes.chunks(BATCH_SIZE) {
        let line_width = |rect: &Rect| ((aspect(rect) * LINE_HEIGHT as f32).ceil() as usize).max(8);
        let width = batch.iter().map(line_width).max().unwrap_or(8);
        let stride = 3 * LINE_HEIGHT * width;
        let mut input = vec![0f32; batch.len() * stride];
        for (rect, slot) in batch.iter().zip(input.chunks_mut(stride)) {
            write_planes(image, *rect, line_width(rect), LINE_HEIGHT, [0.5; 3], [0.5; 3], slot, width);
        }

        let tensor = Tensor::from_array(([batch.len(), 3, LINE_HEIGHT, width], input))?;
        let outputs = session.run(ort::inputs![tensor])?;
        let (shape, logits) = outputs[0].try_extract_tensor::<f32>()?;
        let (steps, classes) = (shape[1] as usize, shape[2] as usize);
        for (rect, line) in batch.iter().zip(logits.chunks(steps * classes)) {
            let (text, score) = decode(line, classes, &dictionary);
            if score >= MIN_TEXT_SCORE && !text.trim().is_empty() {
                fragments.push(Fragment {
                    text: text.trim().to_owned(),
                    x: rect.left as f64,
                    top: rect.top as f64,
                    height: (rect.bottom - rect.top) as f64,
                });
            }
        }
    }
    Ok(fragments)
}

fn aspect(rect: &Rect) -> f32 {
    (rect.right - rect.left) / (rect.bottom - rect.top)
}

/// CTC greedy decoding. Class 0 is the blank and the class after the dictionary is a space.
fn decode(line: &[f32], classes: usize, dictionary: &[&str]) -> (String, f32) {
    let mut text = String::new();
    let (mut previous, mut sum, mut count) = (0, 0f32, 0usize);
    for step in line.chunks(classes) {
        let (class, score) = step
            .iter()
            .enumerate()
            .fold((0, f32::MIN), |best, (i, &value)| if value > best.1 { (i, value) } else { best });
        if class != 0 && class != previous {
            text.push_str(dictionary.get(class - 1).copied().unwrap_or(" "));
            sum += score;
            count += 1;
        }
        previous = class;
    }
    (text, if count == 0 { 0.0 } else { sum / count as f32 })
}
