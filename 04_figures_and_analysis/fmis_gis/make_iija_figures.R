iija_apportion <- read_xlsx(file.path(data_dir, "fmis_mile_markers", "apportionments_2022_2026.xlsx"),
                            sheet = "FY 2021 & Est FY 2022-FY 2026",
                            range = "B15:E65",
                            col_names = c("state", "app_2021", "blank", "app_2022")) %>% select(-blank) %>% 
  mutate(iija_shock = (app_2022 - app_2021),
         iija_shock_pct = iija_shock / app_2021,
         abbr = state.abb[match(state, state.name)]) %>% 
  inner_join(
    state_pop <- read_csv(file.path(data_dir, "fmis_mile_markers", "state_pop_timeseries_fred.csv")) %>% 
      filter(year == 2021) %>% select(-year),
    by = join_by(abbr == state)
  ) %>% 
  mutate(iija_shock_pc = iija_shock / pop,
         app_2021_pc = app_2021 / pop)
  
make_year_comp_df <- function(data) {
data %>%
  filter(!is.na(authconstdate), # double check on cy and ay data, the base plf_gis shouldn't go thorugh here
         !is.na(log_cost_mile)) %>%
  group_by(state_fips) %>%
  summarise(avg_cost_2015_2021 = mean(log_cost_mile[year(authconstdate) >= 2015 & year(authconstdate) <= 2021]),
            avg_cost_2022_2025 = mean(log_cost_mile[year(authconstdate) >= 2022]),
            # per-period project counts feeding each state's average
            n_2015_2021 = sum(year(authconstdate) >= 2015 & year(authconstdate) <= 2021),
            n_2022_2025 = sum(year(authconstdate) >= 2022),
            .groups = "drop") %>%
  inner_join(state_xwalk, by = "state_fips")
}

# label so figures from plf_gis_cy and plf_gis_ay are distinguishable at a glance and in the footnote.
make_year_comp_scatter <- function(data, type_label = "All Project Types",
                                   sample_label = "completion-year sample",
                                   sample_note = "", limits = NULL) {
  df <- make_year_comp_df(data)

  n_dropped <- sum(is.nan(df$avg_cost_2015_2021) | is.nan(df$avg_cost_2022_2025))
  n_pre  <- sum(df$n_2015_2021)
  n_post <- sum(df$n_2022_2025)

  caption_txt <- str_glue(
    "Each point is a state, using summarized FMIS data from 2015 to 2025. ",
    "{n_dropped} states had no projects with mile marker data in one of the two ",
    "periods and are dropped from the plot. Based on {n_pre} projects authorized in ",
    "2015-2021 and {n_post} authorized in 2022-2025. Costs pre-log transformation are ",
    "given in 2025 dollars. {sample_note}"
  )

  p <- ggplot(df, aes(x = avg_cost_2015_2021, y = avg_cost_2022_2025, label = abbr)) +
    geom_point() +
    ggrepel::geom_text_repel(size = 2.4, color = "grey30",
                             max.overlaps = 15,
                             segment.size = 0.2) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
    coord_fixed(ratio = 1) +
    labs(title = "State-level Average log Cost per Mile, 2015-2021 vs. 2022-2025",
         subtitle = str_glue("FMIS Projects with Construction Authorization between 2015-2025 {sample_label}, {type_label}"),
         x = "Average log Cost per Mile (2015-2021)",
         y = "Average log Cost per Mile (2022-2025)",
         caption = caption_txt) +
    qje_theme()

  if (!is.null(limits)) {
    p <- p +
      scale_x_continuous(limits = limits) +
      scale_y_continuous(limits = limits)
  }

  p
}

# =============================================================
# IIJA spending-shock regressions

prep_iija_reg_df <- function(data, ..., start_year = 2015, end_year = 2025) {
  data %>%
    filter(...) %>%
    filter(!is.na(authconstdate), !is.na(log_cost_mile)) %>%
    mutate(auth_year = lubridate::year(authconstdate),
                  post2022  = as.integer(auth_year >= 2022)) %>%
    filter(auth_year >= start_year, auth_year <= end_year) %>%
    inner_join(select(state_xwalk, state_fips, abbr),
                      by = "state_fips") %>%
    inner_join(select(iija_apportion, abbr, iija_shock_pc),
                      by = "abbr")
}

# Fit the preferred FE specification, but fall back to a no-FE version if the
# FE model errors out (e.g. on small subsets where the shock variable becomes
# collinear with the state/year fixed effects). Fixed effects are preserved
# whenever the FE model fits without error.
fit_with_fe_fallback <- function(fe_formula, no_fe_formula, data, vcov, weights,
                                 label = NULL) {
  msg <- if (is.null(label)) "" else str_glue(" for '{label}'")
  tryCatch(
    fixest::feols(fe_formula, data = data, vcov = vcov, weights = weights),
    error = function(e) {
      warning(str_glue(
        "FE specification failed{msg} ({conditionMessage(e)}); ",
        "refitting without fixed effects."), call. = FALSE)
      tryCatch(
        fixest::feols(no_fe_formula, data = data, vcov = vcov, weights = weights),
        error = function(e2) {
          warning(str_glue(
            "No-FE specification also failed{msg} ({conditionMessage(e2)}); ",
            "returning NULL."), call. = FALSE)
          NULL
        }
      )
    }
  )
}

# Build presence dummies for each improvement code in proj_improv_types.
# The field is a semicolon-delimited list, so a project can carry several codes
# at once; factoring it directly would treat each unique combination as its own
# level. Instead we tokenize on ";" and create one 0/1 column per code (~70),
# so each improvement code gets its own fixed effect and a project contributes
# to every code it lists. Returns the augmented df with the dummy column names
# stored in the "ic_dummy_cols" attribute.
add_improv_code_dummies <- function(df, prefix = "ic_") {
  tokens <- stringr::str_split(df$proj_improv_types, ";")
  tokens <- lapply(tokens, function(x) {
    x <- stringr::str_trim(x)
    x[!is.na(x) & !x %in% c("", ".", "NA")]
  })
  codes <- sort(unique(unlist(tokens)))
  if (length(codes) == 0L) {
    attr(df, "ic_dummy_cols") <- character(0)
    return(df)
  }
  dummies <- vapply(codes, function(code) {
    as.integer(vapply(tokens, function(t) code %in% t, logical(1)))
  }, integer(length(tokens)))
  col_names <- paste0(prefix, gsub("[^A-Za-z0-9]", "_", codes))
  dummies <- matrix(dummies, ncol = length(codes),
                    dimnames = list(NULL, col_names))
  df <- dplyr::bind_cols(df, tibble::as_tibble(dummies))
  attr(df, "ic_dummy_cols") <- col_names
  df
}

# first regression specification, just get interaction coefficient
run_iija_did <- function(data, ..., vcov = ~state_fips, weights = NULL,
                         label = NULL) {
  df <- prep_iija_reg_df(data, ...)
  # add one fixed effect per improvement code present in the subset
  df <- add_improv_code_dummies(df)
  ic_cols  <- attr(df, "ic_dummy_cols")
  ic_terms <- if (length(ic_cols)) paste0(" + ", paste(ic_cols, collapse = " + ")) else ""
  m <- fit_with_fe_fallback(
    fe_formula    = as.formula(str_glue(
      "log_cost_mile ~ post2022 * iija_shock_pc + urban_rural + fp_ic{ic_terms} | state_fips + auth_year")),
    no_fe_formula = log_cost_mile ~ post2022 * iija_shock_pc,
    data = df, vcov = vcov, weights = weights, label = label
  )
  # Drop the column entirely when the interaction can't be estimated with a
  # valid clustered SE (e.g. a cost-type subset so thin that the improvement-
  # code dummies exhaust the residual degrees of freedom, so fixest reports
  # "not-available" SEs). We check only the interaction's SE -- a collinear
  # improvement-code dummy losing its own SE shouldn't drop an otherwise-
  # estimable column. Returning NULL keeps such columns out of etable (via
  # compact) rather than surfacing a mismatched Standard-Errors row.
  interaction_se_ok <- function(mod) {
    if (is.null(mod)) return(FALSE)
    ct <- tryCatch(fixest::coeftable(mod), error = function(e) NULL)
    if (is.null(ct)) return(FALSE)
    int <- grep("post2022.*iija_shock_pc|iija_shock_pc.*post2022", rownames(ct))
    length(int) > 0 && all(is.finite(ct[int, "Std. Error"]))
  }
  if (!interaction_se_ok(m)) {
    if (!is.null(label))
      warning(str_glue(
        "Clustered SEs not available for '{label}'; dropping column."),
        call. = FALSE)
    return(NULL)
  }
  m
}

# event study, get interaction with each year rather than post-2022 dummy
run_iija_eventstudy <- function(data, ..., ref_year = 2021,
                                vcov = ~state_fips, weights = NULL,
                                label = NULL) {
  df <- prep_iija_reg_df(data, ...)
  if (!ref_year %in% df$auth_year) {
    lbl <- if (is.null(label)) "" else str_glue(" for '{label}'")
    warning(str_glue(
      "No observations in reference year {ref_year}{lbl}; returning NULL."),
      call. = FALSE)
    return(NULL)
  }
  # Inline the numeric ref_year so it is not treated as a data-set variable.
  fit_with_fe_fallback(
    fe_formula    = as.formula(str_glue(
      "log_cost_mile ~ i(auth_year, iija_shock_pc, ref = {ref_year}) | state_fips + auth_year")),
    no_fe_formula = as.formula(str_glue(
      "log_cost_mile ~ i(auth_year, iija_shock_pc, ref = {ref_year})")),
    data = df, vcov = vcov, weights = weights, label = label
  )
}

# Plot the event-study coefficients (shock x year) with 95% CIs in house style.
# this might be something to come back to **
plot_iija_eventstudy <- function(model, ref_year = 2021,
                                 type_label = "All Project Types",
                                 sample_short = "",
                                 sample_note = "") {
  if (is.null(model)) return(NULL)
  es <- broom::tidy(model, conf.int = TRUE) %>%
    dplyr::filter(stringr::str_detect(term, "iija_shock_pc")) %>%
    dplyr::mutate(year = as.integer(stringr::str_extract(term, "\\d{4}"))) %>%
    dplyr::select(year, estimate, conf.low, conf.high) %>%
    # add back the omitted reference year, pinned to zero
    dplyr::bind_rows(tibble::tibble(year = ref_year, estimate = 0,
                                    conf.low = 0, conf.high = 0)) %>%
    dplyr::arrange(year)

  ggplot(es, aes(year, estimate)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
    geom_vline(xintercept = 2021.5, linetype = "dotted", color = "grey50") +
    geom_line(color = "grey40") +
    geom_pointrange(aes(ymin = conf.low, ymax = conf.high)) +
    scale_x_continuous(breaks = es$year) +
    labs(title = "Event Study: Per-Capita IIJA Shock and log Cost per Mile",
         subtitle = str_glue("{type_label}, {sample_short}"),
         x = "Construction Authorization Year",
         y = str_glue("Shock x Year coefficient"),
         caption = str_glue(
           "Coefficients on the per-capita IIJA shock interacted with authorization-year dummies, ",
           "with state and year fixed effects. {ref_year} is the omitted reference year; the dotted ",
           "line marks the 2022 shock onset. {sample_note} ",
           "Standard errors clustered by state.")) +
    qje_theme()
}

# =============================================================
# Build the full IIJA output set for each project sample
iija_cost_types <- c(
  "All Project Types"                     = NA,
  "Preliminary Engineering" = "has_pe",
  "Right-of-Way"            = "has_row",
  "New Construction"        = "has_new_construction",
  "Rehabilitation"          = "has_rehabilitation",
  "Maintenance"             = "has_maintenance",
  "Reconstruction"          = "has_reconstruction"
)

filter_cost_type <- function(data, col) {
  if (is.na(col)) data else dplyr::filter(data, .data[[col]] == 1)
}

build_iija_outputs <- function(data, sample_label, sample_note, sample_short) {
  scatters <- purrr::imap(iija_cost_types,
                          ~ make_year_comp_scatter(filter_cost_type(data, .x), .y,
                                                   sample_label = sample_label,
                                                   sample_note = sample_note))
  did      <- purrr::imap(iija_cost_types,
                          ~ run_iija_did(filter_cost_type(data, .x),
                                         label = str_glue("{sample_short} - {.y}")))
  es       <- purrr::imap(iija_cost_types,
                          ~ run_iija_eventstudy(filter_cost_type(data, .x),
                                                label = str_glue("{sample_short} - {.y}")))
  es_plots <- purrr::imap(es,
                          ~ plot_iija_eventstudy(.x, type_label = .y,
                                                 sample_short = sample_short,
                                                 sample_note = sample_note))
  list(scatters = scatters, did = did, es = es, es_plots = es_plots)
}

iija_cy <- build_iija_outputs(
  plf_gis_cy, "and Completion Year",
  "Sample is projects with a completion year (completed by 2025) and authorization year; costs deflated by the completion-year CPI.",
  "Sample with Completion Year and Authorization Year")

iija_ay <- build_iija_outputs(
  plf_gis_ay, "",
  "Sample is all projects with a construction authorization year, including those not yet completed; costs deflated by the authorization-year CPI.",
  "Sample with Only Authorization Year")

iija_cy_1yr <- build_iija_outputs(
  plf_gis_cy_1yr, "and Completion Year",
  "Sample is projects with a completion year (completed by 2025) and project length (completion year - authorization year) less than
  1 year; costs deflated by the completion-year CPI.",
  "Sample with Completion Year and Authorization Year, 1-Year Duration Projects"
)

iija_cy_2yr <- build_iija_outputs(
  plf_gis_cy_2yr, "and Completion Year",
  "Sample is projects with a completion year (completed by 2025) and project length (completion year - authorization year) less than
  2 years; costs deflated by the completion-year CPI.",
  "Sample with Completion Year and Authorization Year, 2-Year Duration Projects"
)

iija_cy_codes <- build_iija_outputs(
  plf_gis_cy_iijacodes, "and Completion Year",
  "Sample is projects with a completion year (completed by 2025), authorization year and project code included in IIJA apportionments
  ; costs deflated by the completion-year CPI.",
  "Sample with Completion and Authorization Year, Only IIJA Project Codes"
)

iija_ay_codes <- build_iija_outputs(
  plf_gis_ay, "",
  "Sample is all projects with a construction authorization year, including those not yet completed; costs deflated by the
  authorization-year CPI. Projects have project codes included in IIJA apportionments.",
  "Sample with Authorization Year, Only IIJA Project Codes")

iija_cy_2yr_codes <- build_iija_outputs(
  plf_gis_cy_2yr_iijacodes, "and Completion Year",
  "Sample is projects with a completion year (completed by 2025) and project length (completion year - authorization year) less than
  2 years. Projects have project codes included in IIJA apportionments. Costs deflated by the completion-year CPI.",
  "Sample with Completion Year and Authorization Year, 2-Year Duration Projects and Only IIJA Project Codes"
)

iija_cy_1yr_codes <- build_iija_outputs(
  plf_gis_cy_1yr_iijacodes, "and Completion Year",
  "Sample is projects with a completion year (completed by 2025) and project length (completion year - authorization year) less than
  1 year. Projects have project codes included in IIJA apportionments. Costs deflated by the completion-year CPI.",
  "Sample with Completion Year and Authorization Year, 1-Year Duration Projects and Only IIJA Project Codes"
)

# =============================================================
# create table for counts of observations in pre and post period to get a sense
# of data richness/sparsity

iija_cost_types_short <- c(
  "All"                     = NA,
  "PE" = "has_pe",
  "ROW"            = "has_row",
  "New Const."        = "has_new_construction",
  "Rehab."          = "has_rehabilitation",
  "Maint."             = "has_maintenance",
  "Reconst."          = "has_reconstruction"
)

# pre/post counts for a single sample x construction type
count_pre_post <- function(data, col) {
  df <- prep_iija_reg_df(filter_cost_type(data, col))
  tibble::tibble(pre  = sum(df$post2022 == 0L),
                 post = sum(df$post2022 == 1L))
}

# long table: one row per construction type for a single sample
sample_pre_post_counts <- function(data, sample_label) {
  purrr::imap_dfr(iija_cost_types_short, function(col, type_label) {
    dplyr::bind_cols(
      tibble::tibble(sample = sample_label, type = type_label),
      count_pre_post(data, col)
    )
  })
}

# one row per sample; pre/post columns for each construction type, interleaved
pre_post_counts <- dplyr::bind_rows(
  sample_pre_post_counts(plf_gis_cy,           "Completion +\nAuth Year"),
  sample_pre_post_counts(plf_gis_ay,           "Authorization\nYear"),
  sample_pre_post_counts(plf_gis_cy_2yr,       "Completion + Auth,\n<=2-Year Duration"),
  sample_pre_post_counts(plf_gis_cy_iijacodes, "Completion + Auth,\nIIJA Codes"),
  sample_pre_post_counts(plf_gis_ay_iijacodes, "Authorization Year,\nIIJA Codes"),
  sample_pre_post_counts(plf_gis_cy_2yr_iijacodes, "Completion + Auth\n+ 2-year,\nIIJA Codes")
) %>%
  dplyr::mutate(type = factor(type, levels = names(iija_cost_types_short))) %>%
  tidyr::pivot_wider(names_from  = type,
                     values_from = c(pre, post),
                     names_glue  = "{type}__{.value}") %>%
  # order columns so pre/post sit next to each other within each type
  dplyr::select(sample,
                as.vector(rbind(paste0(names(iija_cost_types_short), "__pre"),
                                paste0(names(iija_cost_types_short), "__post"))))

# LaTeX-friendly print: grouped pre/post header, a fixed-width first column so the
# long sample names wrap, and scale_down so the 15-column table fits the page.
print_pre_post_counts <- function(tbl = pre_post_counts, sample_width = "2.8cm") {
  types <- names(iija_cost_types_short)
  disp  <- tbl
  # Sample labels carry manual "\n" breaks meant for the console; in LaTeX the
  # fixed-width first column wraps them instead, so flatten the newlines to spaces.
  disp$sample <- gsub("\\s*\n\\s*", " ", disp$sample)
  names(disp) <- c("Sample", rep(c("Pre", "Post"), length(types)))

  if (requireNamespace("kableExtra", quietly = TRUE)) {
    knitr::kable(disp, format = "latex", booktabs = TRUE, linesep = "",
                 align = c("l", rep("r", 2 * length(types)))) %>%
      kableExtra::add_header_above(c(" " = 1,
                                     stats::setNames(rep(2, length(types)), types))) %>%
      kableExtra::kable_styling(latex_options = c("hold_position", "scale_down")) %>%
      kableExtra::column_spec(1, width = sample_width)
  } else {
    print(disp)
    invisible(disp)
  }
}
# print_pre_post_counts()
