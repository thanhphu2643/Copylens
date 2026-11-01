#pragma once
#include <stddef.h>

/// One recognized text fragment. Coordinates are normalized, with a top-left origin.
typedef struct {
    const char *text; // UTF-8, NUL-terminated
    double x, y, width, height;
} TextBox;

/// Rebuilds reading order from the fragments. Free the result with text_core_free.
char *text_core_layout(const TextBox *boxes, size_t count);
/// CPU OCR for English/Latin text; returns NULL on failure. Free with text_core_free.
char *text_core_fast_ocr(const unsigned char *rgba, size_t width, size_t height, size_t stride);
void text_core_free(char *text);
