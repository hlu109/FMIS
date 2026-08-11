# ------------------------------------------------------------------------------
# Random and stratified sampling helper functions for pandas DataFrames.
# ------------------------------------------------------------------------------

import pandas as pd


def normalize_stratify_by(stratify_by):
    """Convert stratify_by variable name(s) to a column list, or None if not stratifying."""
    if stratify_by is None:
        return None
    if isinstance(stratify_by, str):
        return [stratify_by]
    return list(stratify_by)


def _allocate_stratum_counts(strata_sizes, n):
    """
    Allocate how many rows to draw from each stratum (largest-remainder method).

    For each stratum s with population size N_s, compute the target share
    n_s = n * N_s / N, take floor(n_s), then assign any leftover rows (n minus
    the sum of floors) one at a time to strata with the largest fractional parts.
    This yields integer counts that sum exactly to n while staying as close as
    possible to proportional representation.

    Parameters:
        strata_sizes (pd.Series): Population count per stratum (index = stratum).
        n (int): Total sample size to allocate.

    Returns:
        pd.Series: Number of rows to sample from each stratum.
    """
    N = strata_sizes.sum()
    raw = n * strata_sizes / N
    counts = raw.apply(lambda x: int(x // 1))
    remainder = n - counts.sum()
    if remainder > 0:
        fractional = (raw - counts).sort_values(ascending=False)
        for stratum in fractional.index[:remainder]:
            counts[stratum] += 1
    return counts


def groupby_key(cols):
    """Return the groupby argument for a the list of variables to stratify on."""
    return cols[0] if len(cols) == 1 else cols


def stratified_sample(df, n, stratify_by=None, seed=42):
    """
    Draw a random sample of n rows from df, optionally stratified by column(s).

    When stratify_by is None, draws a simple random sample. Otherwise allocates
    draws across strata in proportion to stratum size, then samples within each
    stratum without replacement.

    Parameters:
        df (pd.DataFrame): Input data.
        n (int): Number of rows to sample.
        stratify_by (str, list[str], or None): Column(s) defining strata.
        seed (int): Seed for reproducibility.

    Returns:
        pd.DataFrame: Sampled rows.
    """
    cols = normalize_stratify_by(stratify_by)
    if cols is None:
        return df.sample(n=n, random_state=seed)

    group_key = groupby_key(cols)
    strata_sizes = df.groupby(group_key, group_keys=False).size()
    counts = _allocate_stratum_counts(strata_sizes, n)

    parts = []
    for stratum_key, group in df.groupby(group_key, group_keys=False):
        n_s = int(counts[stratum_key])
        if n_s > 0:
            parts.append(group.sample(
                n=min(n_s, len(group)), random_state=seed))

    return pd.concat(parts)


def stratified_sample_summary(df, n, stratify_by, row_indices):
    """
    Summarize population, target allocation, and realized sample counts per stratum.

    Returns None if stratify_by is not set.
    """
    cols = normalize_stratify_by(stratify_by)
    if cols is None:
        return None

    group_key = groupby_key(cols)
    population = df.groupby(group_key, group_keys=False).size()
    allocated = _allocate_stratum_counts(population, n)
    sample = df.loc[row_indices].groupby(group_key, group_keys=False).size()
    return {
        "stratify_cols": cols,
        "population": population,
        "allocated": allocated,
        "sample": sample,
    }
