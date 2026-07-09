* ==============================================================================
* extract interstate route numbers from project titles using regex
* ==============================================================================
/*
    Uses ustrregexm() so that \b word boundaries are available;
    this is the key guard against false positives like "VI-40" (Virgin Islands)
    or "RI-6" (Rhode Island state route), where a letter immediately precedes
    the I and blocks the word boundary.

    Patterns matched:
      I-40  I 40  I40          standard I-prefix, with or without separator
      IH-10 IH 10 IH10         IH-prefix (Texas / Wisconsin convention)
      IR-10 IR 10 IR10         IR-prefix (some state conventions)
      IN-95 IN 95 IN95         IN-prefix (digit required; excludes IN HOUSTON)
      I-70B I-94BL             letter suffixes for business loops / branches
      INTERSTATE 95            spelled out
      FAI-57  FAI 70           Federal Aid Interstate project codes

    Patterns explicitly NOT matched:
      VI-40  VI-70             Virgin Islands routes (\b before I blocked by V)
      RI-6   KY-31             state routes with two-letter prefix
      I/S                      intersection abbreviation (/ not in [-\s]?)
      I-SECTION  ITS           non-digit after I prefix
      BRIDGE NO. I 6-00        bridge IDs (minor residual risk on single-digit
                               routes like I-4 / I-5 / I-8; acceptable tradeoff)
      IN HOUSTON  IN DALLAS    preposition + place name (IN requires digits)
*/

capture program drop extract_routes_regex
program define extract_routes_regex
    /*
    Extracts interstate route numbers from project titles using regex.

    Parameters:
        titlevar (str): Name of the string variable containing the project title
            to parse. Must already exist in the dataset in memory.

    Creates:
        has_route (byte): 1 if any interstate route reference found in title.
        route_1 (str): First matched route string (prefix stripped).
        route_2 (str): Second matched route string (prefix stripped).
        route_3 (str): Third matched route string (prefix stripped).
        route_1_has_char (byte): 1 if route_1 contains a letter suffix (e.g. B, BL).
        route_2_has_char (byte): 1 if route_2 contains a letter suffix.
        route_3_has_char (byte): 1 if route_3 contains a letter suffix.
        route_1_int (numeric): Route number from first match (letters stripped).
        route_2_int (numeric): Route number from second match.
        route_3_int (numeric): Route number from third match.
    */
	syntax , titlevar(string)

	local re_route    `"(\bIH?[-\s]?\d{1,3}[A-Z]{0,2}\b)"'
	local re_ir       `"(\bIR[-\s]?\d{1,3}[A-Z]{0,2}\b)"'
	local re_in       `"(\bIN[-\s]?\d{1,3}\b)"'
	local re_spelled  `"(\bINTERSTATE\s+\d{1,3}\b)"'
	local re_fai      `"(\bFAI[-\s]?\d{1,3}\b)"'
	local re_all `"`re_route'|`re_ir'|`re_in'|`re_spelled'|`re_fai'"'

	gen str title_upper = upper(`titlevar')
	gen byte has_route = ustrregexm(title_upper, `"`re_all'"')

	* extract up to 3 interstate route matches per title
	* find match, strip it from the string, search for more matches
	gen str route_1 = ustrregexs(0) if ustrregexm(title_upper, `"`re_all'"')

	gen str _title_s2 = subinstr(title_upper, route_1, "-----", 1) if !mi(route_1)
	replace _title_s2 = title_upper if mi(route_1)
	gen str route_2 = ustrregexs(0) if ustrregexm(_title_s2, `"`re_all'"')

	gen str _title_s3 = subinstr(_title_s2, route_2, "-----", 1) if !mi(route_2)
	replace _title_s3 = _title_s2 if mi(route_2)
	gen str route_3 = ustrregexs(0) if ustrregexm(_title_s3, `"`re_all'"')

	drop title_upper _title_s2 _title_s3

	local re_prefix `"^(INTERSTATE\s+|FAI[-\s]?|IH?[-\s]?|IR[-\s]?|IN[-\s]?)"'
	foreach v in route_1 route_2 route_3 {
		replace `v' = ustrregexra(`v', `"`re_prefix'"', "") if !mi(`v')
	}

	foreach v in route_1 route_2 route_3 {
		gen byte `v'_has_char = regexm(`v', "[A-Za-z]") if !mi(`v')
		gen str20 `v'_int = ustrregexra(`v', "[A-Za-z]", "") if !mi(`v')
		destring `v'_int, replace
	}

    gen has_route_regex = 0
    replace has_route_regex = 1 if !mi(route_1_int) | !mi(route_2_int) | !mi(route_3_int)
end
