library(readxl)
library(dplyr)
library(stringr)

# This script merges FHWA Highway Statistics FA-3 data from 194? to 2024.

user <- Sys.info()[["user"]]

if (identical(user, "andersonkovesci")) {
  output_dir <- "/Users/andersonkovesci/Dropbox/FHWA cost data/FMIS_graphs"
  raw_data_dir <- "/Users/andersonkovesci/Dropbox/FHWA cost data/Data/Raw"
  intermediate_data_dir <- "/Users/andersonkovesci/Dropbox/FHWA cost data/Data/Intermediate"
} else if (identical(user, "hl2266")) {
  output_dir <- "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data/Output/Hannah"
  raw_data_dir <- "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data/Data/Raw"
  intermediate_data_dir <- "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data/Data/Intermediate"
} else {
  stop("Set your user paths in clean_merge_FA3.R")
}

fa3_dir <- file.path(raw_data_dir, "FHWA_Highway_Statistics", "FA3")

files <- list.files(
  fa3_dir,
  pattern = "^[0-9]{4}_fa3\\.xls[x]?$",
  full.names = TRUE
)

fa3_data <- list()
for (file in files) {
  fname <- basename(file)
  year <- as.integer(substr(fname, 1L, 4L))
  df <- suppressMessages(read_excel(file, sheet = "A", col_names = TRUE))

  # Identify the header row: look in column 1 for the row with "STATE"
  header_row <- df %>%
    mutate(
      row_num = row_number(),
      col1 = str_trim(as.character(.data[[names(df)[1]]]))
    ) %>%
    filter(col1 == "STATE") %>%
    pull(row_num)

  # Build concatenated headers from header_row, header_row+1, header_row+2
  header_idx <- header_row + 0:2
  header_block <- df[header_idx, , drop = FALSE]

  make_full_header <- function(col) {
    parts <- header_block[[col]]
    parts <- ifelse(is.na(parts), "", as.character(parts))
    parts <- trimws(parts)
    # remove trailing single-digit markers like "2/" or "(2)" at the end
    parts <- gsub("\\s*[0-9]/\\s*$", "", parts)
    parts <- gsub("\\s*\\([0-9]\\)\\s*$", "", parts)
    parts <- parts[parts != ""]
    if (!length(parts)) {
      return("")
    }
    paste(parts, collapse = "_")
  }
  full_headers <- vapply(seq_len(ncol(df)), make_full_header, character(1))

  # Keep A and columns whose full header contains "INTERSTATE"
  keep_cols_logical <- (seq_along(full_headers) == 1L) |
    str_detect(toupper(full_headers), "INTERSTATE")
  df <- df[, keep_cols_logical, drop = FALSE]
  full_headers <- full_headers[keep_cols_logical]

  # set the headers
  colnames(df) <- full_headers

  # Drop header rows and anything above them
  df <- df %>% filter(row_number() > header_row + 2L)

  # Filter to U.S. Total row using a whitespace-tolerant regex on column "a"
  df <- df %>%
    filter(str_detect(STATE, "^\\s*U\\.S\\.\\s+Total\\s*$"))

  df$year <- year
  df <- df %>% select(-STATE)

  fa3_data[[year]] <- df
}

fa3 <- dplyr::bind_rows(fa3_data)
# rearrange year to be the first column
fa3 <- fa3 %>% select(year, everything())

write.csv(
  fa3,
  file.path(
    intermediate_data_dir,
    "FHWA_Highway_Statistics/FA3_interstate_1994_2024.csv"
  ),
  row.names = FALSE
)
