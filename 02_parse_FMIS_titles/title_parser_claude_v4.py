import pandas as pd
import re
import numpy as np
import getpass

username = getpass.getuser()
if username == "hl2266":
    input_dir = "your path"
    output_dir = "your path"
elif username == "andersonkovesci":
    input_dir = "/Users/andersonkovesci/Dropbox/FHWA cost data/Data/Hannah sandbox/FMIS_interstate_titles_and_costs.dta"
    output_dir = '/Users/andersonkovesci/Dropbox/FHWA cost data/Data/Hannah sandbox/FMIS_title_description_quality_claude.csv'
else: 
    raise ValueError("Username not recognized. Please set input/output paths manually.")

df = pd.read_stata(input_dir, convert_categoricals=False)
print(f"Loaded {len(df)} rows")

# ═══════════════════════════════════════════════════════════════════════════
# 1. FPN ROUTE CANDIDATE
# ═══════════════════════════════════════════════════════════════════════════
def extract_fpn_route(fpn):
    if pd.isna(fpn) or not fpn:
        return np.nan
    m = re.match(r'[A-Za-z]*(\d{2,4})', str(fpn))
    if not m:
        return np.nan
    digits = m.group(1)
    for width in [3, 2, 4]:
        if len(digits) >= width:
            candidate = digits[:width].lstrip('0')
            if candidate and int(candidate) > 0:
                return int(candidate)
    return np.nan

df['fpn_route_candidate'] = df['federal_project_number'].apply(extract_fpn_route)

# ═══════════════════════════════════════════════════════════════════════════
# 2. ROUTE EXTRACTION
# ═══════════════════════════════════════════════════════════════════════════
def find_all_interstate_routes(title):
    if pd.isna(title) or not title.strip():
        return []
    t = title.upper()
    routes = []
    patterns = [
        r'\bINTERSTATE\s+(\d{1,3})\b',
        r'\bIH\s*(\d{1,3})(?=[^0-9]|$)',
        r'\bFAI[\s-]*(\d{1,3})(?=[^0-9]|$)',
        r'\bIS\s+(\d{1,3})(?=[^0-9]|$)',
        r'\bIR[\s-]+(\d{1,3})(?=[^0-9]|$)',
        r'\bI[\s-]*(\d{1,3})(?=[^0-9]|$)',
    ]
    for pat in patterns:
        for m in re.finditer(pat, t):
            val = int(m.group(1))
            if val not in routes and val > 0:
                routes.append(val)
    return routes

def classify_segment_route(title, all_routes):
    if pd.isna(title) or not title.strip():
        return ('', np.nan, '')
    t = title.upper().strip()
    if not all_routes:
        m = re.search(r'\b(?:US|U\.S\.)\s*(?:RT\.?\s*)?(\d{1,3})\b', t)
        if m: return (m.group(0).strip(), np.nan, 'non-interstate')
        m = re.search(r'\b(?:SR|SH|RTE?|ROUTE)\s*[\s-]?(\d{1,4})\b', t)
        if m: return (m.group(0).strip(), np.nan, 'non-interstate')
        return ('', np.nan, '')
    if len(all_routes) == 1:
        return (_find_raw(t, all_routes[0]), all_routes[0], 'interstate')
    conc = re.search(r'I[\s-]*(\d{1,3})\s*[/&]\s*I?[\s-]*(\d{1,3})', t)
    if conc:
        return (conc.group(0), int(conc.group(1)), 'multiple interstate')
    seg = []
    for rn in all_routes:
        is_xref = False
        for xp in [rf'(?:OVER|UNDER|OV|OVR)\s+I[\s-]*{rn}(?=[^0-9]|$)',
                    rf'(?:OVER|UNDER|OV|OVR)\s+IH\s*{rn}(?=[^0-9]|$)',
                    rf'\bTO\s+I[\s-]*{rn}(?=[^0-9]|$)(?!\s*[-,])',
                    rf'\bAT\s+I[\s-]*{rn}(?=[^0-9]|$)',
                    rf'@\s*I[\s-]*{rn}(?=[^0-9]|$)']:
            if re.search(xp, t):
                is_xref = True; break
        if not is_xref:
            fr_pat = rf'(?:FR(?:OM|\.)?|FM)\s+I[\s-]*{rn}(?=[^0-9]|$)'
            to_pat = rf'\bTO\s+I[\s-]*{rn}(?=[^0-9]|$)'
            route_leads = bool(re.match(rf'(?:I[\s-]*{rn}|IH\s*{rn}|IR[\s-]*{rn}|FAI\s*{rn})', t))
            if (re.search(fr_pat, t) or re.search(to_pat, t)) and not route_leads and len(all_routes) > 1:
                is_xref = True
        if not is_xref:
            seg.append(rn)
    if len(seg) == 1:
        return (_find_raw(t, seg[0]), seg[0], 'interstate')
    elif len(seg) > 1:
        return (_find_raw(t, seg[0]), seg[0], 'multiple interstate')
    else:
        return (_find_raw(t, all_routes[0]), all_routes[0], 'interstate')

def _find_raw(t, rn):
    for pat in [rf'INTERSTATE\s+{rn}', rf'IH\s*{rn}', rf'FAI[\s-]*{rn}',
                rf'IR[\s-]*{rn}', rf'IS\s+{rn}', rf'I[\s-]*{rn}[A-Za-z]?']:
        m = re.search(pat, t)
        if m: return m.group(0).strip()
    return f'I-{rn}'

df['_all_i'] = df['projecttitle'].apply(find_all_interstate_routes)
rr = df.apply(lambda r: classify_segment_route(r['projecttitle'], r['_all_i']), axis=1)
df['route_raw'] = [r[0] for r in rr]
df['route_number'] = [r[1] for r in rr]
df['route_type'] = [r[2] for r in rr]
df.drop(columns=['_all_i'], inplace=True)
print("Route extraction done")
print(df['route_type'].value_counts(dropna=False))

# ═══════════════════════════════════════════════════════════════════════════
# 3. PRECISION SCORING
# ═══════════════════════════════════════════════════════════════════════════
def score_precision(text):
    if not text:
        return 0
    u = text.upper().strip()
    if len(u) < 2:
        return 0
    
    # 6 = Milepost
    if re.search(r'\b(?:MP|MM|MILEPOST|MILE\s*MARKER|MILEPOINT|LM)\s*\d', u):
        return 6
    
    # Offset pattern
    offset = re.search(r'(\d+\.?\d*)\s*MI\.?\s*([NSEW]\.?)\s*(?:OF\s+)?(.*)', u)
    if offset:
        anchor = offset.group(3)
        precise = any(re.search(p, anchor) for p in [
            r'\b(?:SR|SH|US|CR|FM|RT|RTE)\s*[\s-]?\d',
            r'\bI[\s-]*\d{1,3}', r'\bJCT\b', r'\b(?:R\.?R\.|RR|RAILROAD)\b',
            r'\bSTATE\s*LINE\b', r'\bS/?L\b',
            r'\b[A-Z]+\s+COLI\b', r'\bCO\.\s*L', r'\bCO\s+L(?:INE)', r'\bCOUNTY\s*L',
            r'[A-Z]+\s+CO\.?\s*L\b',
            r'\b\w+\s+(?:ST|AVE|BLVD|RD|ROAD|DR|LN|WAY|PKWY|PIKE|HWY)\b',
            r'\bINTERCHANGE\b', r'\bINTCH\b', r'\bI\.C\.?\b', r'\bEXIT\s*\d',
        ])
        return 4 if precise else 3
    # Also catch "X M N OF Y" (abbreviated MI as M)
    offset2 = re.search(r'(\d+\.?\d*)\s*M\s+([NSEW])\s+(?:OF\s+)?(.*)', u)
    if offset2:
        anchor = offset2.group(3)
        precise = any(re.search(p, anchor) for p in [
            r'\b(?:SR|SH|US|CR|FM|RT|RTE)\s*[\s-]?\d',
            r'\bI[\s-]*\d',
            r'\b\w+\s+(?:ST|AVE|BLVD|RD|ROAD|DR|LN|WAY|PKWY|PIKE|HWY)\b',
        ])
        return 4 if precise else 3
    
    # 5 = Intersection/interchange/precise linear feature
    prec5 = [
        r'\b(?:SR|SH|US|CR|FM|RT|RTE|NM|TH|CTH|CSAH|ROUTE)\s*[\s-]?\d{1,4}\b',
        r'\bI[\s-]*\d{1,3}\b',
        r'\b\w+\s+(?:ST(?:REET)?|AVE(?:NUE)?|BLVD|RD|ROAD|DR(?:IVE)?|LN|LANE|WAY|PKWY|PARKWAY|PIKE|HWY)\b',
        r'\bEXIT\s*\d', r'\bINTERCHANGE\b', r'\bINTCH\b', r'\bINTRCH\b',
        r'(?:\s|^)I\.C\.?(?:\s|$|[,;])', r'\s+IC\s*(?:$|[,;])',
        r'\bJCT\.?\s', r'\bJUNCTION\b',
        r'\bSTATE\s*LINE\b', r'\bS/?L\b', r'\bSTATE\s*L\b',
        r'\b[A-Z]+\s+COLI\b', r'\bCO\.\s*L(?:INE)?\.?\b', r'\bCO\s+LINE\b',
        r'\bCOUNTY\s*L(?:INE)?\b', r'[A-Z]+\s+CO\.?\s*L\b',
        r'\b(?:R\.R\.|RR|RAILROAD|RAIL\s*ROAD)\b',
        r'\b(?:RIVER|CREEK|CR\.)\b',
        r'\b(?:OVERPASS|UNDERPASS)\b',
        r'\b[A-Z]+\s+(?:FREEWAY|FWY|EXPWY|EXPRESSWAY)\b',
        r'\b(?:TUNNEL|BRIDGE)\b',
        r'\bT\.?H\.?\s*\d',  # Minnesota trunk highway
        r'\bLA\s+\d',  # Louisiana state route
        r'\bKY\s+\d',  # Kentucky
        r'\bIA\.?\s+\d',  # Iowa
        r'\bILL[\s-]*\d',  # Illinois
        r'\bSC\s+\d',  # South Carolina
        r'\bNC\s+\d',  # North Carolina
        r'\bGA\s+\d',  # Georgia
        r'\bCH[\s-]*\d',  # County highway
        r'\bWV\s+\d',  # West Virginia
        r'\bNJ\s+\d',  # New Jersey
        r'\bVA[\s-]*\d',  # Virginia
        r'\bC/?L\b',  # county line
    ]
    for p in prec5:
        if re.search(p, u):
            return 5
    
    # 1 = Vague
    if re.search(r'\b(?:STATEWIDE|VARIOUS|DISTRICTWIDE|DIST\.?\s*WIDE|REGIONWIDE|MULTIPLE)\b', u):
        return 1
    # 2 = Named place
    return 2


# ═══════════════════════════════════════════════════════════════════════════
# 4. ENDPOINT EXTRACTION
# ═══════════════════════════════════════════════════════════════════════════

# Comprehensive work-type keyword pattern for cleaning
WORK_TYPE_RE = (
    r'(?:PE|ROW|R/W|R-O-W|CONSTR\w*|RESURF\w*|OVERLAY|PAVING|PAVT|'
    r'SIGN\w*|LIGHT\w*|GUARD\w*|FENCE|SEAL\w*|LAND\w*|MAINT\w*|REHAB\w*|'
    r'WIDEN\w*|REPL\w*|REPAIR\w*|SAFETY|UTIL\w*|ILLUM\w*|SURF\w*|DECK\w*|'
    r'PAINT\w*|PATCH\w*|MARK\w*|DRAIN\w*|STUDY|DESIGN|MISC|INCID\w*|'
    r'INSTALL\w*|MODERN\w*|UPGRADE\w*|IMPROV\w*|MILL\w*|MICRO\w*|PMS|HTP|'
    r'HMA|PCC|BIT\w*|CONC\w*|SEED\w*|EROSI\w*|BARRIER|NOISE|MEDIAN|CLEAR\w*|'
    r'DEMO\w*|SURVEY|STRS|STRUCT\w*|ACQUI\w*|FENC\w*|DELINEAT\w*|MONUMENT\w*|'
    r'RIGHT\w*|LANDSCAP\w*|ARCHAEO\w*|GRADING|HIGH\s+TYPE|APPROACHES|SUBBASE|'
    r'PAVEMENT|P\.?E\.?|PURCHASE\s+\w+|ARCHAEOLOGICAL|GR[\.,\s]|DR[\.,\s]|'
    r'G&D\w*|EMBANKMENT|EXCAVAT\w*|CHANNELIZ\w*|RUMBLE\w*|CABLE\w*|'
    r'RECONST\w*|RECONSTRUCT\w*|REHABILITAT\w*|PREVENTIVE|PREVENTATIVE|'
    r'MOVE\s|ADD\s|NEW\s|WELD\w*|SLIDE\s|JOINT\w*|EPOXY|SCOUR|RIPRAP|'
    r'RCI|CPR|HPP|HBP|STP|HRRR|HSIP|CMAQ|NFA|NHPP|STBG)'
)

def clean_ep(text):
    if not text:
        return ''
    # Remove trailing work type keywords (iteratively)
    for _ in range(3):
        new = re.sub(
            rf'\s*[,;]?\s*{WORK_TYPE_RE}\s*$',
            '', text, flags=re.I
        ).strip().rstrip('.,;:- ')
        if new == text:
            break
        text = new
    if re.match(r'^[NSEW]\.?$', text):
        return ''
    return text


def strip_route_prefix(tu):
    """Remove leading route designation(s) from title."""
    # Standard patterns
    stripped = re.sub(
        r'^(?:(?:RT\.?\s+)?(?:INTERSTATE|IH|I|IR|FAI|IS)[\s-]*\d{1,3}[A-Za-z]?'
        r'(?:\s*[/&,]\s*(?:I|IH|IR|FAI)?[\s-]*\d{1,3}[A-Za-z]?)*)\s*[,;:]?\s*',
        '', tu
    ).strip()
    # SR X (I-Y) pattern (Florida)
    stripped = re.sub(r'^SR\s*\d+[A-Z]?\s*\(I-?\d+\)\s*[,;:]?\s*', '', stripped).strip()
    # Ohio coded: "CUY IR 480 05.40"
    stripped = re.sub(r'^[A-Z]{2,3}\s+IR\s+\d{1,4}\s*', '', stripped).strip()
    # "US-I-25," prefix
    stripped = re.sub(r'^US-I-\d{1,3}\s*[,;:]?\s*', '', stripped).strip()
    # Leading dash/comma
    stripped = stripped.lstrip('-,;: ')
    return stripped if stripped else tu


def extract_project_type(title):
    tu = title.upper()
    if ';' in title:
        parts = title.split(';')
        last = parts[-1].strip()
        if len(last) < 80 and re.search(
            r'(?:PE|ROW|CONSTR|RESURF|BRIDGE|SIGN|LIGHT|GUARD|PAVE|REHAB|WIDEN|'
            r'REPAIR|SAFETY|UTIL|DESIGN|STUDY|MAINT|INSTALL|OVERLAY|MILL|PATCH|'
            r'MARK|DRAIN|SEED|LANDSCAPE|FENCE|GRAD|SURVEY|CONST|ENGINEER|'
            r'PLANNING|PRELIMINARY|RIGHT|ACQUI|EMERGENCY|RESTOR|DECK|PAINT|'
            r'SUBSTRUCTURE|SUPERSTRUCTURE)', last, re.I):
            return last
    if ',' in title:
        parts = title.rsplit(',', 1)
        last = parts[-1].strip()
        if len(last) < 80 and re.search(
            r'(?:PE|ROW|R/W|CONSTR|RESURF|OVERLAY|PAV|BRIDGE|BR[\.\s]|SIGN|LIGHT|'
            r'GUARD|FENCE|SEAL|GR[\.,\s]|DR[\.,\s]|LAND|MAINT|REHAB|WIDEN|REPL|'
            r'REPAIR|SAFE|UTIL|ILLUM|SURF|DECK|PAINT|PATCH|MARK|DRAIN|STUDY|'
            r'DESIGN|MISC|INCID|INSTALL|UPGRADE|IMPROV|MILL|MICRO|PMS|HTP|HMA|PCC|'
            r'BIT|CONC|SEED|EROSI|BARRIER|NOISE|MEDIAN|CLEAR|DEMO|SURVEY|STRS|'
            r'STRUCT|ACQUI|FENC|DELINEAT|MONUMENT|RIGHT|LANDSCAP|ARCHAEO|LIGHTING|'
            r'GRADING|CHANNELIZ|EMBANKMENT|EXCAVAT|RECONST|SLIDE)', last, re.I):
            return last
    return ''


def looks_like_location(text):
    if not text: return False
    u = text.upper()
    pats = [
        r'\b(?:ST|AVE|BLVD|RD|DR|LN|HWY|PKWY|PIKE|CREEK|RIVER|BRIDGE|BR\b|'
        r'COUNTY|CO\.?|CITY|TOWN|TWP|JCT|JUNCTION|INTERCHANGE|INTCH|EXIT|'
        r'RAMP|STATE\s*LINE|S/?L|C/?L|I\.C|TUNNEL|OVERPASS|UNDERPASS)',
        r'\b(?:US|SR|SH|CR|FM|RT|RTE|NM|TH|CTH|CSAH)\s*\d',
        r'\bI[\s-]*\d{1,3}\b',
        r'\d+\s*MI', r'\bCOLI\b', r'\bCO\.\s*L',
        r'\b(?:RIVER|CREEK|LAKE)\b',
    ]
    for p in pats:
        if re.search(p, u): return True
    if re.match(r'^[A-Z][A-Za-z\.\' ]+$', text.strip()) and len(text.strip()) < 40:
        return True
    return False


def is_work_type_start(text):
    """Check if text starts with a work type description."""
    u = text.upper().strip()
    return bool(re.match(
        r'(?:PE\b|ROW\b|R/W|RESURFAC|REHAB|OVERLAY|PAVING|SIGNING|LIGHTING|'
        r'GUARDRAIL|GRADING|MILLING|PATCHING|SEEDING|LANDSCAPING|FENCING|'
        r'DRAINAGE|WIDENING|CONSTRUCTION|PRELIMINARY|DESIGN|STUDY|MAINTENANCE|'
        r'SAFETY\s+IMPROV|EROSION|STRIPING|DELINEATION|ILLUMINATION|BARRIER|'
        r'MEDIAN|CABLE|REPAIR|REPLACE|INSTALL|NOISE|SURVEY|SEAL\s|CLEARING|'
        r'DEMOLITION|PAVEMENT\s*MARK|RUMBLE|RECONST|WIDEN\s+FREEWAY|'
        r'MOVE\s|ADD\s+LANE|PREVENTIVE|PREVENTATIVE|BRIDGE\s+(?:REHAB|DECK|'
        r'PAINT|REPLAC|WIDEN|REPAIR|MAINT|INSPECT)|MILL\s+AND|RCI\s|CPR\s|'
        r'HAZARD|HIGH\s+FRICTION|SURFACING|SHOULDER|SLIDE\s+REPAIR|'
        r'RESURFACE|REHABILITAT|RIGHT\s+OF\s+WAY|MODIFY|UPGRADE|IMPROVE)', u
    ))


def parse_title(title):
    result = {
        'endpoint_a_raw': '', 'endpoint_b_raw': '',
        'precision_a': 0, 'precision_b': 0,
        'milepost_start': np.nan, 'milepost_end': np.nan,
        'project_type_raw': ''
    }
    if pd.isna(title) or not title.strip():
        return result
    
    tu = title.strip().upper()
    result['project_type_raw'] = extract_project_type(title.strip())
    
    # ── Mileposts (check first, highest priority) ──
    mp = _try_mileposts(tu)
    if mp:
        result.update(mp)
        return result
    
    # ── Ohio coded format: "CUY IR 480 05.40" -> milepost ──
    ohio = re.match(r'^([A-Z]{2,3})\s+IR\s+(\d{1,4})\s+(\d+\.?\d*)', tu)
    if ohio:
        county_code = ohio.group(1)
        mp_val = float(ohio.group(3))
        # Check for second milepost: "05.40/10.77" or "(05.40) (10.77)"
        rest = tu[ohio.end():]
        m2 = re.match(r'\s*[/\s]\s*(?:VAR|\d+\.?\d*)', rest)
        mp2 = np.nan
        if m2 and m2.group(0).strip() not in ('VAR', ''):
            try:
                mp2 = float(m2.group(0).strip().lstrip('/'))
            except ValueError:
                pass
        result['endpoint_a_raw'] = f'{county_code} MP {ohio.group(3)}'
        result['precision_a'] = 6
        result['milepost_start'] = mp_val
        if not np.isnan(mp2):
            result['endpoint_b_raw'] = f'{county_code} MP {mp2}'
            result['precision_b'] = 6
            result['milepost_end'] = mp2
        return result
    
    # Normalize directional.TO
    tu_norm = re.sub(r'([NSEW])\.TO\s', r'\1 TO ', tu)
    tu_norm = re.sub(r'([NSEW]),?\s*TO\s', r'\1 TO ', tu_norm)
    
    loc = strip_route_prefix(tu_norm)
    
    # ── Check if title starts with work type (location is elsewhere) ──
    # e.g., "Mill and Overlay on I-35 in Coffey County"
    # e.g., "Bridge deck replacement on I-55 over Sangamon River"
    if is_work_type_start(tu):
        # Look for location after "ON I-XX" or "ON IH XX" 
        loc_after = _try_location_after_on(tu_norm)
        if loc_after:
            result['endpoint_a_raw'] = loc_after[0]
            result['endpoint_b_raw'] = loc_after[1] if len(loc_after) > 1 else ''
            result['precision_a'] = score_precision(loc_after[0])
            result['precision_b'] = score_precision(loc_after[1]) if len(loc_after) > 1 and loc_after[1] else 0
            return result
    
    # ── FROM...TO ──
    ft = _try_from_to(tu_norm)
    if ft:
        result['endpoint_a_raw'] = ft[0]
        result['endpoint_b_raw'] = ft[1]
        result['precision_a'] = score_precision(ft[0])
        result['precision_b'] = score_precision(ft[1]) if ft[1] else 0
        return result
    
    # ── BETWEEN...AND ──
    bt = _try_between(tu_norm)
    if bt:
        result['endpoint_a_raw'] = bt[0]
        result['endpoint_b_raw'] = bt[1]
        result['precision_a'] = score_precision(bt[0])
        result['precision_b'] = score_precision(bt[1]) if bt[1] else 0
        return result
    
    # ── A TO B (no FROM) ──
    at = _try_a_to_b(loc)
    if at:
        result['endpoint_a_raw'] = at[0]
        result['endpoint_b_raw'] = at[1]
        result['precision_a'] = score_precision(at[0])
        result['precision_b'] = score_precision(at[1]) if at[1] else 0
        return result
    
    # ── Dash-separated ──
    da = _try_dash(loc)
    if da:
        result['endpoint_a_raw'] = da[0]
        result['endpoint_b_raw'] = da[1]
        result['precision_a'] = score_precision(da[0])
        result['precision_b'] = score_precision(da[1]) if da[1] else 0
        return result
    
    # ── AT / @ / UNDER / OVER / NEAR / ON ──
    ai = _try_at_in(loc, tu_norm)
    if ai:
        result['endpoint_a_raw'] = ai
        result['precision_a'] = score_precision(ai)
        return result
    
    # ── Offset: "X MI N OF Y" ──
    off = _try_offset(tu_norm)
    if off:
        result['endpoint_a_raw'] = off
        result['precision_a'] = score_precision(off)
        return result
    
    # ── Leading location name ──
    ll = _try_leading(loc)
    if ll:
        result['endpoint_a_raw'] = ll
        result['precision_a'] = score_precision(ll)
        return result
    
    # ── Fallback: any location-looking text in the stripped portion ──
    fb = _try_fallback(loc)
    if fb:
        result['endpoint_a_raw'] = fb
        result['precision_a'] = score_precision(fb)
        return result
    
    return result


def _try_mileposts(tu):
    pats = [
        r'(?:MP|MM|MILEPOST|MILE\s*MARKER|MILEPOINT)\s*(\d+\.?\d*)\s*(?:TO|-|&|AND)\s*(?:MP|MM|MILEPOST|MILE\s*MARKER|MILEPOINT)?\s*(\d+\.?\d*)',
        r'FR(?:OM|\.?)?\s*(?:MP|MM|MILEPOST)\s*(\d+\.?\d*)\s*TO\s*(?:MP|MM|MILEPOST)?\s*(\d+\.?\d*)',
        r'BETWEEN\s*(?:MP|MM)\s*(\d+\.?\d*)\s*[&]\s*(\d+\.?\d*)',
        r'(?:LM|LOGMILE)\s*(\d+\.?\d*)\s*(?:TO|-|&|AND)\s*(?:LM|LOGMILE)?\s*(\d+\.?\d*)',
    ]
    for p in pats:
        m = re.search(p, tu)
        if m:
            return {'endpoint_a_raw': f'MP {m.group(1)}', 'endpoint_b_raw': f'MP {m.group(2)}',
                    'precision_a': 6, 'precision_b': 6,
                    'milepost_start': float(m.group(1)), 'milepost_end': float(m.group(2))}
    m = re.search(r'(?:MP|MM|MILEPOST|MILE\s*MARKER|LM)\s*(\d+\.?\d*)', tu)
    if m:
        return {'endpoint_a_raw': f'MP {m.group(1)}', 'endpoint_b_raw': '',
                'precision_a': 6, 'precision_b': 0,
                'milepost_start': float(m.group(1)), 'milepost_end': np.nan}
    return None


def _try_location_after_on(tu):
    """For titles like 'Mill and Overlay on I-35 in Coffey County'."""
    # Find "ON I-XX" or "ON IH XX" then get location after it
    m = re.search(
        r'\bON\s+(?:I[\s-]*\d{1,3}|IH\s*\d{1,3})\s*[,;]?\s*(.*)',
        tu
    )
    if m:
        rest = m.group(1).strip()
        if not rest:
            return None
        # Try FROM...TO in the rest
        ft = re.search(r'(?:FR(?:OM|\.)?|FM)\s+(.+?)\s+TO\s+(.+?)(?:\s*[,;]|$)', rest)
        if ft:
            return (clean_ep(ft.group(1)), clean_ep(ft.group(2)))
        # Try BETWEEN...AND
        bt = re.search(r'BETWEEN\s+(.+?)\s+AND\s+(.+?)(?:\s*[,;]|$)', rest)
        if bt:
            return (clean_ep(bt.group(1)), clean_ep(bt.group(2)))
        # Try IN/AT/NEAR
        loc = re.search(r'(?:IN|AT|NEAR|@|OVER|UNDER)\s+(.+?)(?:\s*[,;.]|$)', rest)
        if loc:
            ep = clean_ep(loc.group(1))
            if ep and len(ep) > 2:
                return (ep,)
        # Just take whatever's there as a location
        ep = clean_ep(rest)
        if ep and len(ep) > 2 and not is_work_type_start(ep):
            return (ep,)
    
    # Also try "OVER <feature> ON I-XX"
    m = re.search(r'\bOVER\s+(.+?)\s+ON\s+(?:I[\s-]*\d|IH\s*\d)', tu)
    if m:
        ep = clean_ep(m.group(1))
        if ep and len(ep) > 2:
            return (ep,)
    
    # "AT <loc> ON I-XX"
    m = re.search(r'(?:\bAT\b|@)\s+(.+?)\s+ON\s+(?:I[\s-]*\d|IH\s*\d)', tu)
    if m:
        ep = clean_ep(m.group(1))
        if ep and len(ep) > 2:
            return (ep,)
    
    return None


def _try_from_to(tu):
    # Try FROM...TO
    m = re.search(
        r'(?:FR(?:OM|\.)?|FM)\s+(.+?)\s+TO\s+(.+?)(?:\s*[,;]\s*(?:[A-Z&]{2})|$)',
        tu
    )
    if m:
        a = clean_ep(m.group(1))
        b = clean_ep(m.group(2))
        if a and len(a) > 1:
            return (a, b)
    # More aggressive
    m = re.search(r'(?:FR(?:OM|\.)?|FM)\s+(.+?)\s+TO\s+(.+)', tu)
    if m:
        a = clean_ep(m.group(1))
        b = clean_ep(m.group(2))
        if a and len(a) > 1:
            return (a, b if b else '')
    # FROM A, direction (no TO)
    m = re.search(
        rf'(?:FR(?:OM|\.)?|FM)\s+(.{{3,}}?)(?:\s*[,;]\s*{WORK_TYPE_RE})',
        tu
    )
    if m:
        a = clean_ep(m.group(1))
        if a and len(a) > 1:
            return (a, '')
    # FROM A at end
    m = re.search(r'(?:FR(?:OM|\.)?|FM)\s+(.{3,})', tu)
    if m:
        a = clean_ep(m.group(1))
        if a and len(a) > 2:
            return (a, '')
    return None


def _try_between(tu):
    m = re.search(r'\bBETWEEN\s+(.+?)\s+AND\s+(.+?)(?:\s*[,;]|$)', tu)
    if m:
        a = clean_ep(m.group(1))
        b = clean_ep(m.group(2))
        if a and len(a) > 1:
            return (a, b)
    # BETWEEN A & B
    m = re.search(r'\bBETWEEN\s+(.+?)\s*&\s*(.+?)(?:\s*[,;]|$)', tu)
    if m:
        a = clean_ep(m.group(1))
        b = clean_ep(m.group(2))
        if a and len(a) > 1:
            return (a, b)
    return None


def _try_a_to_b(loc):
    m = re.match(r'^(.+?)\s+TO\s+(.+?)(?:\s*[,;]\s*|\s*$)', loc)
    if m:
        a = clean_ep(m.group(1))
        b = clean_ep(m.group(2))
        if a and len(a) > 2 and (looks_like_location(a) or not is_work_type_start(a)):
            return (a, b)
    return None


def _try_dash(loc):
    m = re.match(r'^(.+?)\s*[-]\s*(.+?)(?:\s*[,;]\s*|\s*$)', loc)
    if m:
        a = m.group(1).strip()
        b = clean_ep(m.group(2))
        if (a and b and len(a) > 2 and len(b) > 2 and
            looks_like_location(a) and looks_like_location(b) and
            not is_work_type_start(a) and not is_work_type_start(b)):
            return (a, b)
    return None


def _try_at_in(loc, full):
    for pat in [r'(?:\bAT\b|@)\s+(.+?)(?:\s*[,;(]\s*|\s*$)',
                r'\bUNDER\s+(.+?)(?:\s*[,;]\s*|\s*$)',
                r'\bNEAR\s+(.+?)(?:\s*[,;]\s*|\s*$)',
                r'\bOVER\s+(.+?)(?:\s*[,;]\s*|\s*$)',
                r'\bIN\s+([A-Z][A-Z\s\.\']+?)(?:\s*[,;]\s*|\s*$)']:
        m = re.search(pat, loc)
        if m:
            l = clean_ep(m.group(1))
            if l and len(l) > 2 and not is_work_type_start(l):
                return l
    # Also try on full title
    for pat in [r'(?:\bAT\b|@)\s+(.+?)(?:\s*[,;(]\s*|\s*$)',
                r'\bUNDER\s+(.+?)(?:\s*[,;]\s*|\s*$)',
                r'\bOVER\s+(.+?)(?:\s*[,;]\s*|\s*$)']:
        m = re.search(pat, full)
        if m:
            l = clean_ep(m.group(1))
            if l and len(l) > 2 and not is_work_type_start(l):
                return l
    return None


def _try_offset(tu):
    m = re.search(
        r'(\d+\.?\d*\s*MI\.?\s*[NSEW]\.?\s*(?:OF\s+)?(?:.+?))(?:\s*[,;]\s*|\s*$)',
        tu
    )
    if m:
        loc = clean_ep(m.group(1))
        if loc and len(loc) > 5:
            return loc
    # Also "X M N OF Y" (abbreviated)
    m = re.search(
        r'(\d+\.?\d*\s*M\s+[NSEW]\s+(?:OF\s+)?(?:.+?))(?:\s*[,;]\s*|\s*$)',
        tu
    )
    if m:
        loc = clean_ep(m.group(1))
        if loc and len(loc) > 5:
            return loc
    return None


def _try_leading(loc):
    m = re.match(r'^([A-Z][A-Z\s\.\'&/]+?)(?:\s*[,;:]\s*)', loc)
    if m:
        l = m.group(1).strip()
        if looks_like_location(l) and len(l) > 2 and len(l) < 70 and not is_work_type_start(l):
            return l
    return None


def _try_fallback(loc):
    """Last resort: look for any location-like text in the stripped portion."""
    # Look for road references
    m = re.search(r'(\b(?:US|SR|SH|CR|FM|RT|RTE)\s*[\s-]?\d{1,4})\b', loc)
    if m:
        return m.group(1)
    # Look for street names
    m = re.search(r'(\b[A-Z]+\s+(?:ST|AVE|BLVD|RD|ROAD|DR|LN|HWY|PKWY)\b)', loc)
    if m:
        return m.group(1)
    # Look for EXIT
    m = re.search(r'(EXIT\s*\d+)', loc)
    if m:
        return m.group(1)
    # JCT
    m = re.search(r'(JCT\.?\s+\S+(?:\s+\S+)?)', loc)
    if m:
        return clean_ep(m.group(1))
    # Interchange
    m = re.search(r'(\b\w+\s+INTERCHANGE\b)', loc)
    if m:
        return m.group(1)
    # City/county in the full text
    m = re.search(r'\bIN\s+([A-Z][A-Z]+(?:\s+[A-Z]+)?)\b', loc)
    if m and not is_work_type_start(m.group(1)):
        return m.group(1)
    return None


# ═══════════════════════════════════════════════════════════════════════════
# APPLY
# ═══════════════════════════════════════════════════════════════════════════
print("Parsing descriptions (first pass)...")
parsed_desc = df['projectdescription'].apply(lambda x: parse_title(x) if pd.notna(x) else {
    'endpoint_a_raw': '', 'endpoint_b_raw': '',
    'precision_a': 0, 'precision_b': 0,
    'milepost_start': np.nan, 'milepost_end': np.nan,
    'project_type_raw': ''
})
for col in ['endpoint_a_raw', 'endpoint_b_raw', 'precision_a', 'precision_b',
            'milepost_start', 'milepost_end', 'project_type_raw']:
    df[col] = [r[col] for r in parsed_desc]

# ── Fallback: parse title when description is missing endpoint(s) ──
missing_a = df['precision_a'] == 0
missing_b = df['precision_b'] == 0
any_missing = missing_a | missing_b
print(f"Falling back to projecttitle for {any_missing.sum()} rows "
      f"({missing_a.sum()} missing A, {missing_b.sum()} missing B)...")

parsed_title = df.loc[any_missing, 'projecttitle'].apply(parse_title)
title_results = list(parsed_title)
title_index = df.loc[any_missing].index
title_df = pd.DataFrame(title_results, index=title_index)

# For rows missing A: fill all fields from title
for col in ['endpoint_a_raw', 'endpoint_b_raw', 'precision_a', 'precision_b',
            'milepost_start', 'milepost_end']:
    df.loc[missing_a, col] = title_df.loc[missing_a, col]

# For rows where A is fine but B is missing: only fill B fields from title
missing_b_only = missing_b & ~missing_a
df.loc[missing_b_only, 'endpoint_b_raw'] = title_df.loc[missing_b_only, 'endpoint_b_raw']
df.loc[missing_b_only, 'precision_b']    = title_df.loc[missing_b_only, 'precision_b']
df.loc[missing_b_only, 'milepost_end']   = title_df.loc[missing_b_only, 'milepost_end']

# project_type_raw: only fill from title where description left it blank
title_no_type_mask = any_missing & (df['project_type_raw'] == '')
df.loc[title_no_type_mask, 'project_type_raw'] = title_df.loc[
    title_no_type_mask[any_missing].values, 'project_type_raw'
].values

# Track source
df['location_source'] = 'description'
df.loc[missing_a & (df['precision_a'] > 0), 'location_source'] = 'title'
df.loc[missing_b_only & (df['precision_b'] > 0), 'location_source'] = 'title (b only)'
df.loc[df['precision_a'] == 0, 'location_source'] = 'none'

print("\n=== PRECISION A ===")
print(df['precision_a'].value_counts().sort_index())
print("\n=== PRECISION B ===")
print(df['precision_b'].value_counts().sort_index())
print("\n=== LOCATION SOURCE ===")
print(df['location_source'].value_counts())

# Export
out_cols = [
    'recipientid', 'federal_project_number', 'projecttitle', 'projectdescription',
    'state_fips', 'county_fips', 'countyid', 'year', 'total_cost_bills_adjusted',
    'fpn_route_candidate', 'route_raw', 'route_number', 'route_type',
    'endpoint_a_raw', 'endpoint_b_raw', 'precision_a', 'precision_b',
    'milepost_start', 'milepost_end', 'project_type_raw', 'location_source'
]
df[out_cols].to_csv(output_dir, index=False)
print(f"\nExported {len(df)} rows to {output_dir}")

# Spot checks
print("\n=== SPOT CHECKS ===")
tests = [
    "CUY IR 480 05.40",
    "HAM IR 70/75 VAR",
    "LOR IR 0090 17.53, Deck Replacement",
    "I-93 AT U.S.302 WEST OF LITTLETON, SAFETY IMPROVEMENTS",
    "I 75@SASHABOW RD, DECK SURFACING",
    "I-94 under Glenlord Road and Cleveland Avenue",
    "I-57,UNDER TR-245,4 M S MATTOON, HWY SEP",
    "Mill and Overlay on I-35 in Coffey County",
    "Bridge deck replacement on I-55 over Sangamon River, 2.2 Mi S of US 36",
    "Safety improvements on I-94 between Canal St and MLK Dr in Chicago",
    "I-5 JCT SR 34, N 7.04M, GR, DR, HT PAVE",
    "I-15 13800 SOUTH ST.TO DRAPER CROSSROADS, R/W UTIL.ADJ.RELOCATION",
    "I-40 E, GALLUP INTERCHANGE E, 4R, PAVE, BR REHAB, MISC CONST",
    "I-55,N OF US-150 TO GM&O RR W OF BLOOMINGTON, LANDSCAPING",
    "REST AREA S OF MANCHESTER RD ON I90, PE",
    "I-244,FROM 41ST ST.N.TO 21ST ST., STRUCTURES",
    "I-29 IN CB FR I-80 N.TO 9TH AVE, GR.BR.&INCD.PAVING",
    "I-81-1 MI.SOUTH OF WILKES-BARRE,NE, RIGHT-OF-WAY FENCE",
    "I-80 N,ISAACS CANYON-SEBREE, PE,PLMX,SEAL SHOULDERS",
    "I-95 Aux Lanes (NB & SB) between Route 288 and Route 10",
    "I-70,ILL-130,NE OF GREENUP, HWY.SEP.&APPROACHES",
    "DEWITT & CICERO:INTERSTATE 481 BETWEEN THE FORREST INTERCHANGE AND INTERSTATE 81",
    "Pavement patching on I-72 (EB) between the Riverton and Illiopolis interchanges.",
    "HAZARD ELIMINATION AND SAFETY ON IH 35, SH 16, FM 1283",
    "I-24, BR ON WALDRON RD LM 2.17, WIDENING FOR BR, UTILITIES",
]

for tt in tests:
    r = parse_title(tt)
    routes = find_all_interstate_routes(tt)
    seg = classify_segment_route(tt, routes)
    print(f"\n  '{tt[:80]}'")
    print(f"    route: {seg[0]} ({seg[1]}) [{seg[2]}]")
    print(f"    ep_a: '{r['endpoint_a_raw'][:55]}'  prec: {r['precision_a']}")
    print(f"    ep_b: '{r['endpoint_b_raw'][:55]}'  prec: {r['precision_b']}")
    if not np.isnan(r['milepost_start']): print(f"    mp: {r['milepost_start']} - {r['milepost_end']}")