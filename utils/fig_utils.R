# This script contains helper functions for figure generation.

# Setup ------------------------------------
library(dplyr)
library(tidyverse)
library(stringr)
library(ggplot2)

# ==============================================================================

# Wrap and concatenate figure notes for ggplot captions.
wrap_figure_notes <- function(notes, width) {
  # Returns:
  #   A single character string with each note wrapped individually and
  #   all notes concatenated with newline separators.

  lines <- if (is.null(notes)) character(0) else as.character(notes)
  if (length(lines) == 0L) {
    return("")
  }
  wrapped_lines <- vapply(
    lines,
    function(x) paste(strwrap(x, width = width), collapse = "\n"),
    character(1)
  )
  paste(wrapped_lines, collapse = "\n")
}
