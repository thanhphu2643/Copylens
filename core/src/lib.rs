//! Turns unordered OCR fragments into plain text: groups them into lines,
//! keeps paragraph breaks and normalizes to NFC (Vietnamese diacritics paste
//! correctly and stay searchable).

mod fast_ocr;

use std::ffi::{c_char, CStr, CString};
use unicode_normalization::UnicodeNormalization;

#[repr(C)]
pub struct TextBox {
    pub text: *const c_char,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

pub(crate) struct Fragment {
    pub(crate) text: String,
    pub(crate) x: f64,
    pub(crate) top: f64,
    pub(crate) height: f64,
}

impl Fragment {
    fn center(&self) -> f64 {
        self.top + self.height / 2.0
    }
}

pub(crate) fn layout(mut fragments: Vec<Fragment>) -> String {
    fragments.sort_by(|a, b| a.center().total_cmp(&b.center()));

    // Fragments on one line overlap vertically by more than half their height.
    let mut lines: Vec<Vec<Fragment>> = Vec::new();
    for fragment in fragments {
        match lines.last_mut() {
            Some(line)
                if (fragment.center() - line[0].center()).abs()
                    < fragment.height.min(line[0].height) / 2.0 =>
            {
                line.push(fragment)
            }
            _ => lines.push(vec![fragment]),
        }
    }

    let bounds: Vec<(f64, f64)> = lines
        .iter()
        .map(|line| {
            let top = line.iter().map(|f| f.top).fold(f64::INFINITY, f64::min);
            let bottom = line.iter().map(|f| f.top + f.height).fold(f64::NEG_INFINITY, f64::max);
            (top, bottom)
        })
        .collect();
    let gaps: Vec<f64> = bounds.windows(2).map(|w| w[1].0 - w[0].1).collect();
    // A blank line shows up as a gap a bit under one text height, well above the usual gap.
    let paragraph_gap = (0.75 * lower_median(bounds.iter().map(|(t, b)| b - t).collect()))
        .max(1.8 * lower_median(gaps.clone()));

    let mut out = String::new();
    for (i, line) in lines.iter_mut().enumerate() {
        if i > 0 {
            out.push_str(if gaps[i - 1] > paragraph_gap { "\n\n" } else { "\n" });
        }
        line.sort_by(|a, b| a.x.total_cmp(&b.x));
        let words: Vec<&str> = line.iter().map(|f| f.text.as_str()).collect();
        out.push_str(&words.join(" "));
    }
    out.nfc().collect()
}

/// The lower median, so one large gap among two doesn't count as "typical".
fn lower_median(mut values: Vec<f64>) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    values.sort_by(f64::total_cmp);
    values[(values.len() - 1) / 2]
}

/// # Safety
/// `boxes` must point to `count` valid boxes whose `text` is NUL-terminated or null.
#[no_mangle]
pub unsafe extern "C" fn text_core_layout(boxes: *const TextBox, count: usize) -> *mut c_char {
    let boxes = if boxes.is_null() { &[] } else { std::slice::from_raw_parts(boxes, count) };
    let fragments = boxes
        .iter()
        .filter(|b| !b.text.is_null())
        .map(|b| Fragment {
            text: CStr::from_ptr(b.text).to_string_lossy().trim().to_owned(),
            x: b.x,
            top: b.y,
            height: b.height,
        })
        .filter(|f| !f.text.is_empty())
        .collect();
    // C strings can't contain NUL, so neither can the joined output.
    CString::new(layout(fragments)).unwrap_or_default().into_raw()
}

/// CPU OCR that never waits on the system's model compiler. English/Latin text only.
/// Returns null on failure; free the result with `text_core_free`.
///
/// # Safety
/// `rgba` must point to `height` rows of `stride` bytes, each holding `width` RGBA pixels.
#[no_mangle]
pub unsafe extern "C" fn text_core_fast_ocr(
    rgba: *const u8,
    width: usize,
    height: usize,
    stride: usize,
) -> *mut c_char {
    if rgba.is_null() || width == 0 || height == 0 || stride < width * 4 {
        return std::ptr::null_mut();
    }
    let pixels = std::slice::from_raw_parts(rgba, stride * height);
    match fast_ocr::recognize(&fast_ocr::Image { pixels, width, height, stride }) {
        Ok(text) => CString::new(text).unwrap_or_default().into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// # Safety
/// `text` must come from a `text_core_*` function and be freed only once.
#[no_mangle]
pub unsafe extern "C" fn text_core_free(text: *mut c_char) {
    if !text.is_null() {
        drop(CString::from_raw(text));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frag(text: &str, x: f64, top: f64) -> Fragment {
        Fragment { text: text.into(), x, top, height: 0.1 }
    }

    #[test]
    fn orders_fragments_into_lines_left_to_right() {
        let text = layout(vec![
            frag("cuối", 0.0, 0.2),
            frag("phải", 0.5, 0.01),
            frag("trái", 0.0, 0.0),
        ]);
        assert_eq!(text, "trái phải\ncuối");
    }

    #[test]
    fn evenly_spaced_lines_have_no_blank_lines() {
        let text = layout(vec![frag("a", 0.0, 0.0), frag("b", 0.0, 0.3), frag("c", 0.0, 0.6)]);
        assert_eq!(text, "a\nb\nc");
    }

    #[test]
    fn large_gap_starts_a_paragraph() {
        let text = layout(vec![
            frag("a", 0.0, 0.0),
            frag("b", 0.0, 0.12),
            frag("c", 0.0, 0.24),
            frag("d", 0.0, 0.7),
        ]);
        assert_eq!(text, "a\nb\nc\n\nd");
    }

    #[test]
    fn normalizes_decomposed_vietnamese_to_nfc() {
        let text = layout(vec![frag("Vie\u{0323}\u{0302}t", 0.0, 0.0)]);
        assert_eq!(text, "Việt");
    }

    #[test]
    fn fast_ocr_reads_english_screenshot() {
        let file = std::fs::File::open("tests/fixtures/english.png").unwrap();
        let mut reader = png::Decoder::new(std::io::BufReader::new(file)).read_info().unwrap();
        let mut pixels = vec![0; reader.output_buffer_size().unwrap()];
        let info = reader.next_frame(&mut pixels).unwrap();
        assert_eq!(info.color_type, png::ColorType::Rgba);

        let text = fast_ocr::recognize(&fast_ocr::Image {
            pixels: &pixels,
            width: info.width as usize,
            height: info.height as usize,
            stride: info.line_size,
        })
        .unwrap();

        assert!(text.contains("The quick brown fox jumps over the lazy dog"), "{text}");
        assert!(text.contains("support@example.com"), "{text}");
        assert!(text.lines().count() >= 10, "{text}");
    }

    #[test]
    fn no_fragments_gives_empty_text() {
        assert_eq!(layout(vec![]), "");
    }

    #[test]
    fn ffi_round_trip_skips_null_and_blank_text() {
        let hello = CString::new("xin chào").unwrap();
        let blank = CString::new("  ").unwrap();
        let boxes = [
            TextBox { text: hello.as_ptr(), x: 0.0, y: 0.0, width: 1.0, height: 0.1 },
            TextBox { text: blank.as_ptr(), x: 0.0, y: 0.5, width: 1.0, height: 0.1 },
            TextBox { text: std::ptr::null(), x: 0.0, y: 0.9, width: 1.0, height: 0.1 },
        ];
        unsafe {
            let out = text_core_layout(boxes.as_ptr(), boxes.len());
            assert_eq!(CStr::from_ptr(out).to_str().unwrap(), "xin chào");
            text_core_free(out);
        }
    }
}
