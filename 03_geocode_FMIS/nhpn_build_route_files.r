####################################################################################
## nhpn_build_route_files.r
##
## PURPOSE
##   Turn the raw NHPN edge network into per-route line files, one file per sign
##   TYPE (interstate, US, state, ...). For each requested type it writes TWO
##   versions, each with ONE observation per distinct route (e.g. a single line
##   for I-5):
##
##     * <type>_by_sign.gpkg    - routes aggregated by SIGNT + SIGNN (the national
##                                sign identity, e.g. all "I 5" segments -> one row)
##     * <type>_by_routeid.gpkg - routes aggregated by ROUTE_ID (NHPN's own route
##                                key, which is effectively state-local)
##
##   Concurrencies: a segment can carry up to three signs (SIGN1/SIGN2/SIGN3).
##   For the by-sign version every segment is counted under EACH sign it carries
##   (melt over the three slots), so overlapping routes never drop a shared
##   segment ("append this to each ... avoid missing segments").
##
##   Gaps: after unioning a route's segments, any remaining disjoint pieces are
##   bridged with the STITCHING TECHNIQUE from fmis_geometry_extraction_stitching_test.r
##   (undirected weighted graph -> connected components -> Dijkstra bridge between
##   dangling ends, accepting a path only if it is <= stitch_ratio x the straight-
##   line gap and the gap itself is <= stitch_max_m). The reference version keyed
##   the graph on TIGER node ids (TNIDF/TNIDT); NHPN has no node ids, so here the
##   nodes are SYNTHESIZED by snapping each segment's endpoints to a snap_tol_m
##   grid. Everything downstream of node construction is the same algorithm.
##
## ENTRY POINT
##   build_nhpn_routes(types = c("I","U"), ...)   # see the function for all args
##
## NOTE
##   Read-only w.r.t. the source data; only writes the output gpkgs. This file is
##   meant to be sourced and then called; the example call at the bottom is
##   commented out on purpose (nothing runs on source()).
####################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
})

####Config / defaults####
  NHPN_SHP <- paste0("C:/Users/fm557/YLS Dropbox/Finn Meffe/FHWA cost data/Data/Raw/NHPN/",
                     "NTAD_National_Highway_Planning_Network_-4963173249024654263/",
                     "National_Highway_Planning_Network.shp")
  OUT_DIR_DEFAULT <- "C:/Users/fm557/YLS Dropbox/Finn Meffe/FHWA cost data/Data/Intermediate/NHPN_routes"
  WORK_CRS <- 5070        # CONUS Albers (metres) for all length/topology maths

  ## friendly file-name label per SIGNT1 code (fallback: type_<code>)
  TYPE_LABEL <- c(I = "interstate", U = "us_route", S = "state_route",
                  C = "county_route", O = "other", N = "national_forest",
                  F = "federal", M = "misc", T = "toll")

####Small utilities####
  `%||%` <- function(a, b) if (is.null(a)) b else a

  type_label <- function(code) unname(TYPE_LABEL[code] %||% NA) %||% paste0("type_", code)

  ## most common non-blank value (for summarising an attribute over a route)
  modal <- function(x) {
    x <- x[!is.na(x) & x != ""]
    if (!length(x)) return(NA_character_)
    names(sort(table(x), decreasing = TRUE))[1]
  }

  ## combine a set of line edges and merge touching parts into as few lines as
  ## possible. st_combine does NOT node at crossings (st_union would, which
  ## over-fragments a route); st_line_merge then joins contiguous segments.
  merge_lines <- function(edges) {
    st_line_merge(st_combine(st_geometry(edges)))
  }

  ## number of disjoint line parts in a length-1 (multi)linestring sfc
  n_parts <- function(g) length(st_cast(st_cast(g, "MULTILINESTRING"), "LINESTRING"))

####Read + prepare the network (once)####
  ## Reads only the columns we need, explodes to single LINESTRINGs, projects to
  ## WORK_CRS, and stamps a stable per-edge id (.eid). Returns an sf.
  read_nhpn <- function(path = NHPN_SHP, work_crs = WORK_CRS, verbose = TRUE) {
    lyr <- sf::st_layers(path)$name[1]
    q <- sprintf(paste("SELECT ROUTE_ID, STFIPS, LNAME,",
                       "SIGNT1, SIGNN1, SIGNT2, SIGNN2, SIGNT3, SIGNN3 FROM \"%s\""), lyr)
    if (verbose) message("reading NHPN ...")
    x <- suppressWarnings(sf::st_read(path, query = q, quiet = TRUE))
    x <- st_zm(x, drop = TRUE)
    x <- st_transform(x, work_crs)
    x <- x[!st_is_empty(x), ]
    ## NHPN is already ~100% LINESTRING; only explode the handful of MULTILINESTRING
    ## rows. (A blanket st_cast(st_cast(...)) over all 626k features cost ~40s to
    ## produce zero extra rows.)
    mp <- which(st_geometry_type(x) == "MULTILINESTRING")
    if (length(mp))
      x <- rbind(x[-mp, ], suppressWarnings(st_cast(x[mp, ], "LINESTRING")))
    x$.eid <- seq_len(nrow(x))
    if (verbose) message(sprintf("  %d edges after explode", nrow(x)))
    x
  }

####Stitching (ported from fmis_geometry_extraction_stitching_test.r)####
  ## --- minimal undirected weighted graph, CSR adjacency (base R, no igraph) -----
  graph_build <- function(from, to, w) {
    nodes <- unique(c(from, to))
    fi <- match(from, nodes); ti <- match(to, nodes)
    n  <- length(nodes); m  <- length(fi)
    h  <- c(fi, ti); tl <- c(ti, fi); e <- c(seq_len(m), seq_len(m))
    o  <- order(h)
    list(nodes = nodes, n = n, m = m, w = w,
         adj_to = tl[o], adj_e = e[o],
         ptr = c(0L, cumsum(tabulate(h, nbins = n))))
  }

  graph_components <- function(g) {
    comp <- integer(g$n); k <- 0L
    for (s in seq_len(g$n)) {
      if (comp[s]) next
      k <- k + 1L; comp[s] <- k; stack <- s
      while (length(stack)) {
        v <- stack[length(stack)]; stack <- stack[-length(stack)]
        lo <- g$ptr[v] + 1L; hi <- g$ptr[v + 1L]
        if (hi >= lo) {
          nb <- g$adj_to[lo:hi]; nb <- nb[comp[nb] == 0L]
          if (length(nb)) { comp[nb] <- k; stack <- c(stack, nb) }
        }
      }
    }
    list(membership = comp, no = k)
  }

  ## dijkstra; stops once every target is settled or maxdist is exceeded
  graph_dijkstra <- function(g, s, targets = integer(0), maxdist = Inf) {
    dist <- rep(Inf, g$n); dist[s] <- 0
    prev_v <- integer(g$n); prev_e <- integer(g$n); done <- logical(g$n)
    need <- setdiff(targets, s)
    repeat {
      d2 <- dist; d2[done] <- Inf
      u  <- which.min(d2)
      if (!length(u) || !is.finite(d2[u]) || d2[u] > maxdist) break
      done[u] <- TRUE
      if (length(need) && all(done[need])) break
      lo <- g$ptr[u] + 1L; hi <- g$ptr[u + 1L]
      if (hi >= lo) {
        j  <- lo:hi
        nb <- g$adj_to[j]; ee <- g$adj_e[j]
        nd <- dist[u] + g$w[ee]
        up <- nd < dist[nb]
        if (any(up)) {
          dist[nb[up]]   <- nd[up]
          prev_v[nb[up]] <- u
          prev_e[nb[up]] <- ee[up]
        }
      }
    }
    list(dist = dist, prev_v = prev_v, prev_e = prev_e)
  }

  graph_path_edges <- function(r, s, t) {
    out <- integer(0); v <- t
    while (v != s) {
      e <- r$prev_e[v]; if (e == 0L) return(integer(0))
      out <- c(out, e); v <- r$prev_v[v]
    }
    out
  }

  ## --- node synthesis (replaces TNIDF/TNIDT): snap each edge's first/last vertex
  ##     to a snap_tol_m grid and use "gx:gy" as the node key --------------------
  node_key <- function(xy, snap) sprintf("%.0f:%.0f", round(xy[1] / snap), round(xy[2] / snap))
  node_xy  <- function(key, snap) as.numeric(strsplit(key, ":", fixed = TRUE)[[1]]) * snap

  ## vectorized: ONE st_coordinates() call for the whole set, then take the first
  ## and last vertex of each edge via its L1 group id. (A per-geometry R loop here
  ## was the dominant cost - >2 min on a single state's fill pool.)
  edge_end_nodes <- function(edges_m, snap) {
    co <- sf::st_coordinates(edges_m)          # X, Y, L1 (feature id) for LINESTRINGs
    L  <- co[, ncol(co)]
    fi <- !duplicated(L)                       # first vertex of each edge
    la <- !duplicated(L, fromLast = TRUE)      # last  vertex of each edge
    list(f = sprintf("%.0f:%.0f", round(co[fi, 1] / snap), round(co[fi, 2] / snap)),
         t = sprintf("%.0f:%.0f", round(co[la, 1] / snap), round(co[la, 2] / snap)))
  }

  ## bridge disjoint components of `matched` (a minimal .eid + geometry sf) using
  ## `fill` (candidate edges, same schema). Returns list(edges, n_added).
  ## Mirrors stitch_route() in the reference script step-for-step.
  stitch_geoms <- function(matched, fill, snap, ratio, max_m, buf_m) {
    none <- list(edges = matched, n_added = 0L)
    if (is.null(matched) || nrow(matched) < 2) return(none)

    en <- edge_end_nodes(matched, snap)
    mf <- en$f; mt <- en$t
    mw <- as.numeric(st_length(matched))

    gm <- graph_build(mf, mt, mw)
    cm <- graph_components(gm)
    if (cm$no < 2) return(none)                       # already one piece

    dn_i <- which(diff(gm$ptr) == 1L)                 # degree-1 (dangling) nodes
    if (length(dn_i) < 2) return(none)
    dn   <- gm$nodes[dn_i]
    memb <- cm$membership[dn_i]
    dcoord <- t(vapply(dn, node_xy, numeric(2), snap = snap))
    dsf <- st_as_sf(data.frame(x = dcoord[, 1], y = dcoord[, 2]),
                    coords = c("x", "y"), crs = st_crs(matched))

    ## candidate fill: not already in the match, and near a dangling end
    if (is.null(fill) || nrow(fill) == 0) return(none)
    fp <- fill[!fill$.eid %in% matched$.eid, ]
    if (!nrow(fp)) return(none)
    ## cheap bbox pre-crop before the (costly) distance test: drop fill outside the
    ## match's bounding box expanded by buf_m.
    b <- st_bbox(matched)
    b["xmin"] <- b["xmin"] - buf_m; b["ymin"] <- b["ymin"] - buf_m
    b["xmax"] <- b["xmax"] + buf_m; b["ymax"] <- b["ymax"] + buf_m
    fp <- fp[lengths(st_intersects(fp, st_as_sfc(b))) > 0, ]
    if (!nrow(fp)) return(none)
    fp <- fp[lengths(st_is_within_distance(fp, dsf, buf_m)) > 0, ]
    if (!nrow(fp)) return(none)

    ef <- edge_end_nodes(fp, snap)
    g <- graph_build(c(mf, ef$f), c(mt, ef$t), c(mw, as.numeric(st_length(fp))))
    is_fill <- c(rep(FALSE, nrow(matched)), rep(TRUE, nrow(fp)))
    fill_ix <- c(rep(NA_integer_, nrow(matched)), seq_len(nrow(fp)))

    di <- match(dn, g$nodes); ok0 <- !is.na(di)
    di <- di[ok0]; memb <- memb[ok0]; dcoord <- dcoord[ok0, , drop = FALSE]
    if (length(di) < 2) return(none)

    cap  <- ratio * max_m
    runs <- lapply(di, function(a) graph_dijkstra(g, a, targets = di, maxdist = cap))
    D    <- t(vapply(runs, function(r) r$dist[di], numeric(length(di))))
    E2   <- as.matrix(dist(dcoord))                   # straight-line gaps

    pr <- which(upper.tri(D), arr.ind = TRUE)
    ok <- memb[pr[, 1]] != memb[pr[, 2]] &
          is.finite(D[pr]) &
          E2[pr] <= max_m &
          D[pr]  <= ratio * pmax(E2[pr], 1)
    pr <- pr[ok, , drop = FALSE]
    if (!nrow(pr)) return(none)
    pr <- pr[order(D[pr]), , drop = FALSE]            # shortest bridges first

    comp <- memb; add <- integer(0)
    for (j in seq_len(nrow(pr))) {
      a <- pr[j, 1]; b <- pr[j, 2]
      if (comp[a] == comp[b]) next
      eids <- graph_path_edges(runs[[a]], di[a], di[b])
      if (!length(eids)) next
      add  <- c(add, fill_ix[eids][is_fill[eids]])
      comp[comp == comp[b]] <- comp[a]
    }
    add <- unique(add[!is.na(add)])
    if (!length(add)) return(none)

    list(edges = rbind(matched[, c(".eid")], fp[add, c(".eid")]), n_added = length(add))
  }

####Aggregate one route (combine + optional stitch) -> single geometry####
  ## eids          : edge ids belonging to this route
  ## edges_min     : minimal sf (.eid + geometry) to subset from
  ## fill_provider : zero-arg fn returning the candidate fill sf (called lazily,
  ##                 only when we actually intend to stitch, so we never pay to
  ##                 assemble a multi-state fill pool for a route we then skip)
  route_geometry <- function(eids, edges_min, fill_provider, stitch, p) {
    sub    <- edges_min[edges_min$.eid %in% eids, c(".eid")]
    merged <- merge_lines(sub)
    np     <- n_parts(merged)

    ## Stitch only routes with a FEW disjoint pieces. A full divided highway is
    ## inherently hundreds/thousands of parts (each carriageway + interchange
    ## breaks) - those are not gaps to bridge, and sewing them is intractable, so
    ## above stitch_max_components we leave the route as a single multipart row.
    if (!stitch || np < 2 || np > p$stitch_max_components)
      return(list(geom = merged, n_parts = np, n_stitched = 0L))

    fill_min <- fill_provider()
    if (is.null(fill_min) || nrow(fill_min) == 0)
      return(list(geom = merged, n_parts = np, n_stitched = 0L))

    st <- stitch_geoms(sub, fill_min, p$snap_tol_m, p$stitch_ratio,
                       p$stitch_max_m, p$stitch_buf_m)
    merged2 <- merge_lines(st$edges)
    list(geom = merged2, n_parts = n_parts(merged2), n_stitched = st$n_added)
  }

####Melt the three sign slots into long (type, num) rows####
  ## keeps only rows whose sign type is in `types`; carries .eid, STFIPS, and the
  ## other signs on that segment (for a concurrency note on the output).
  melt_signs <- function(edges, types) {
    at <- sf::st_drop_geometry(edges)
    slots <- lapply(1:3, function(k) {
      tibble(.eid   = at$.eid,
             STFIPS = at$STFIPS,
             signt  = at[[paste0("SIGNT", k)]],
             signn  = at[[paste0("SIGNN", k)]])
    })
    long <- bind_rows(slots) %>%
      filter(!is.na(signt), signt != "", signt %in% types) %>%
      mutate(signn = ifelse(is.na(signn), "", signn),
             sign  = paste0(signt, signn))
    long
  }

####Build one output file for one (aggregation, type)####
  ## returns the assembled sf (also written to disk by the caller)
  build_one <- function(type, aggregation, edges, fill_by_state, p, verbose) {
    stopifnot(aggregation %in% c("sign", "routeid"))

    ## ---- assemble the (route_key -> edge ids, state set, attrs) groups --------
    if (aggregation == "sign") {
      long <- melt_signs(edges, type)
      if (!nrow(long)) return(NULL)
      keycol <- if (p$sign_scope == "state") paste(long$STFIPS, long$sign) else long$sign
      groups <- split(long, keycol)
      attr_of <- function(gr) {
        list(signt = gr$signt[1], signn = gr$signn[1],
             sign  = gr$sign[1],
             stfips = paste(sort(unique(gr$STFIPS)), collapse = ";"),
             route_id = NA_character_, lname = NA_character_)
      }
    } else {                                              # routeid
      at   <- sf::st_drop_geometry(edges)
      keep <- which(at$SIGNT1 == type & !is.na(at$SIGNT1))
      if (!length(keep)) return(NULL)
      long <- tibble(.eid = at$.eid[keep], STFIPS = at$STFIPS[keep],
                     ROUTE_ID = at$ROUTE_ID[keep], SIGNT1 = at$SIGNT1[keep],
                     SIGNN1 = at$SIGNN1[keep], LNAME = at$LNAME[keep])
      keycol <- if (p$sign_scope == "state") paste(long$STFIPS, long$ROUTE_ID) else long$ROUTE_ID
      groups <- split(long, keycol)
      attr_of <- function(gr) {
        list(signt = modal(gr$SIGNT1), signn = modal(gr$SIGNN1),
             sign  = paste0(modal(gr$SIGNT1), modal(gr$SIGNN1) %||% ""),
             stfips = paste(sort(unique(gr$STFIPS)), collapse = ";"),
             route_id = gr$ROUTE_ID[1], lname = modal(gr$LNAME))
      }
    }

    edges_min <- edges[, c(".eid")]
    if (verbose) message(sprintf("  [%s / %s] %d routes", type, aggregation, length(groups)))

    ## ---- build each route ----------------------------------------------------
    rows <- vector("list", length(groups))
    for (i in seq_along(groups)) {
      gr  <- groups[[i]]
      sts <- unique(gr$STFIPS)
      ## lazy: only assembled if route_geometry decides to stitch this route
      fill_provider <- function() {
        if (!p$stitch) return(NULL)
        fl <- fill_by_state[intersect(sts, names(fill_by_state))]
        if (length(fl)) do.call(rbind, fl) else NULL
      }

      rg  <- route_geometry(gr$.eid, edges_min, fill_provider, p$stitch, p)
      a   <- attr_of(gr)
      rows[[i]] <- tibble(
        route_id   = a$route_id,
        sign       = a$sign,
        signt      = a$signt,
        signn      = a$signn,
        lname      = a$lname,
        stfips     = a$stfips,
        n_segments = nrow(gr),
        n_parts    = rg$n_parts,
        n_stitched = rg$n_stitched,
        geometry   = rg$geom)
      if (verbose && i %% 250 == 0) message(sprintf("    %d / %d", i, length(groups)))
    }

    out <- st_as_sf(bind_rows(rows))
    st_geometry(out) <- "geometry"
    out
  }

####MAIN ENTRY POINT####
  ## types        : character vector of SIGNT1 codes to build, e.g. c("I","U").
  ##                One output file per type per aggregation.
  ## aggregations : which versions to build - "sign" (SIGNT+SIGNN) and/or "routeid".
  ## stitch       : close route gaps with the ported stitching technique.
  ## sign_scope   : "national" keys routes on sign/route_id alone (I 5 = one object
  ##                nationwide); "state" prefixes STFIPS so same-numbered routes in
  ##                different states stay separate.
  ## fill_types   : SIGNT1 codes usable as gap-fill edges (NULL = any NHPN edge,
  ##                including unsigned connectors/ramps - most permissive).
  ## snap_tol_m   : endpoints within this distance are treated as the same node.
  ## stitch_ratio / stitch_max_m / stitch_buf_m : identical meaning to the reference
  ##                script (accept a bridge <= ratio x gap; never bridge a gap over
  ##                max_m; only search fill within buf_m of a dangling end).
  ## stitch_max_components : skip stitching for routes with more disjoint pieces
  ##                than this. A long divided highway is inherently ~1000s of parts
  ##                (two carriageways + interchange breaks), which are not gaps and
  ##                cannot be sewn tractably; such routes stay one multipart row.
  ##                Stitching is meant for routes with a handful of real gaps.
  ## out_format   : "gpkg" (default) or "geojson".
  build_nhpn_routes <- function(types,
                                nhpn_path    = NHPN_SHP,
                                out_dir      = OUT_DIR_DEFAULT,
                                aggregations = c("sign", "routeid"),
                                stitch       = TRUE,
                                sign_scope   = c("national", "state"),
                                fill_types   = NULL,
                                snap_tol_m   = 2,
                                stitch_ratio = 1.5,
                                stitch_max_m = 5000,
                                stitch_buf_m = 2000,
                                stitch_max_components = 40,
                                work_crs     = WORK_CRS,
                                out_crs      = 4326,
                                out_format   = c("gpkg", "geojson"),
                                verbose      = TRUE) {
    sign_scope <- match.arg(sign_scope)
    out_format <- match.arg(out_format)
    aggregations <- match.arg(aggregations, several.ok = TRUE)
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

    p <- list(stitch = stitch, sign_scope = sign_scope, snap_tol_m = snap_tol_m,
              stitch_ratio = stitch_ratio, stitch_max_m = stitch_max_m,
              stitch_buf_m = stitch_buf_m, stitch_max_components = stitch_max_components)

    edges <- read_nhpn(nhpn_path, work_crs, verbose)

    ## pre-split candidate fill edges by state (gaps are always intra-state); this
    ## keeps the per-route spatial search local and cheap.
    fill_by_state <- NULL
    if (stitch) {
      fedges <- if (is.null(fill_types)) edges
                else edges[!is.na(edges$SIGNT1) & edges$SIGNT1 %in% fill_types, ]
      fill_by_state <- split(fedges[, c(".eid")], fedges$STFIPS)
    }

    ext <- if (out_format == "gpkg") "gpkg" else "geojson"
    written <- character(0)
    for (type in types) {
      lab <- type_label(type)
      for (agg in aggregations) {
        out <- build_one(type, agg, edges, fill_by_state, p, verbose)
        if (is.null(out) || nrow(out) == 0) {
          if (verbose) message(sprintf("  [%s / %s] nothing to write", type, agg))
          next
        }
        out <- st_transform(out, out_crs)
        suffix <- if (agg == "sign") "by_sign" else "by_routeid"
        f <- file.path(out_dir, sprintf("nhpn_%s_%s.%s", lab, suffix, ext))
        suppressWarnings(st_write(out, f, delete_dsn = TRUE, quiet = !verbose))
        written <- c(written, f)
        if (verbose) message(sprintf("  wrote %s (%d routes)", basename(f), nrow(out)))
      }
    }
    invisible(written)
  }
