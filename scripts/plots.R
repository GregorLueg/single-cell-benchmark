# Figures for the README and docs. Reads docs/figures/results_long.csv
# (uv run scripts/tables.py --long results > docs/figures/results_long.csv).
# Usage: Rscript scripts/plots.R

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(patchwork)
})

fig_dir <- "docs/figures"
dt_all <- fread(file.path(fig_dir, "results_long.csv"))
dt <- dt_all[startsWith(size, "parse")]

# one per framework family, from the lto "hat" palette
family_cols <- c(
  bixverse = "#0F8096",
  Scanpy = "#E8351E",
  scrapper = "#17A769",
  Seurat = "#852F88",
  CyteArc = "#D98E04"
)
surface <- "#fcfcfb"
ink <- "#0b0b0b"
ink_2 <- "#52514e"
grid_col <- "#e4e3df"

column_order <- c(
  "bixverse mtx", "bixverse h5ad",
  "Scanpy mtx", "Scanpy h5ad", "Scanpy dask",
  "scrapper mtx", "scrapper h5ad", "scrapper HDF5",
  "Seurat std mtx", "Seurat std h5ad", "Seurat BPCells",
  "CyteArc mtx", "CyteArc h5ad"
)
step_order <- c(
  "load", "qc", "normalise", "hvg", "pca", "harmony", "knn_snn", "cluster",
  "cluster_fast", "umap", "dge", "tsne_default", "tsne_fft", "tsne_quick"
)
size_labels <- c(
  parse_100k = "100k (69,412 cells)",
  parse_500k = "500k (346,259 cells)",
  parse_full = "full (684,932 cells)"
)

dt[, family := sub(" .*", "", column)]
dt[, column := factor(column, levels = column_order)]
dt[, step := factor(step, levels = step_order)]

theme_bench <- function(base_size = 10) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.background = element_rect(fill = surface, colour = NA),
      panel.background = element_rect(fill = surface, colour = NA),
      panel.grid.major = element_line(colour = grid_col, linewidth = 0.3),
      panel.grid.minor = element_blank(),
      text = element_text(colour = ink),
      axis.text = element_text(colour = ink_2),
      plot.title = element_text(face = "bold", size = base_size + 1),
      plot.subtitle = element_text(colour = ink_2),
      plot.caption = element_text(colour = ink_2, hjust = 0),
      legend.position = "bottom",
      strip.text = element_text(face = "bold", hjust = 0)
    )
}

#### figure 1: time and memory per size ---------------------------------------

run_summary <- function(d) {
  d[, .(
    family = sub(" .*", "", column[1]),
    # a run that died in a tSNE step still has a time without tSNE
    died = {
      bad <- status != "ok" & !grepl("^tsne", step)
      if (any(bad)) paste(status[bad][1], "at", step[bad][1]) else NA_character_
    },
    no_tsne = sum(seconds[!grepl("^tsne|^cluster_fast", step)], na.rm = TRUE),
    peak_gb = peak_gb[1]
  ), by = .(column, size)]
}

runs <- run_summary(dt)
runs[, status := fifelse(is.na(died), "ok", "failed")]
runs[status != "ok", no_tsne := NA_real_]

scaling_bars <- function(labels, title, file) {
  r <- run_summary(dt_all[size %in% names(labels)])
  r[!is.na(died), no_tsne := NA_real_]
  r[, size_label := factor(labels[size], levels = labels)]
  r[, column := factor(column, levels = rev(column_order))]
  x_min <- 5

  p_time <- ggplot(r, aes(y = column)) +
    geom_col(aes(x = no_tsne, fill = family), width = 0.75, na.rm = TRUE) +
    geom_text(
      aes(x = no_tsne, label = format(round(no_tsne), big.mark = ",", trim = TRUE)),
      hjust = -0.15, size = 3.6, colour = ink, na.rm = TRUE
    ) +
    geom_text(
      data = r[!is.na(died)], aes(x = x_min, label = died),
      hjust = 0, size = 3.6, colour = ink_2, nudge_x = 0.02
    ) +
    scale_x_log10(
      limits = c(x_min, NA), oob = scales::oob_keep, breaks = c(10, 100, 1000), labels = c("10 s", "100 s", "1,000 s"),
      expand = expansion(mult = c(0, 0.3))
    ) +
    facet_wrap(~size_label, nrow = 1) +
    labs(title = "Without tSNE", x = NULL, y = NULL)

  p_mem <- ggplot(r, aes(y = column)) +
    geom_col(aes(x = peak_gb, fill = family), width = 0.75) +
    geom_vline(xintercept = 24, linetype = "dotted", colour = ink_2) +
    geom_text(
      aes(
        x = peak_gb, label = paste0(sprintf("%.1f", peak_gb), fifelse(is.na(died), "", ", died")),
        hjust = fifelse(peak_gb > 18, 1.1, -0.15), colour = peak_gb > 18
      ),
      size = 3.6, show.legend = FALSE
    ) +
    scale_colour_manual(values = c(`FALSE` = ink, `TRUE` = "#ffffff")) +
    scale_x_continuous(breaks = c(0, 8, 16, 24), labels = c("0", "8", "16", "24"),
                       expand = expansion(mult = c(0, 0.08))) +
    facet_wrap(~size_label, nrow = 1) +
    labs(title = "Peak memory (GB); dotted: the 24 GB cap", x = NULL, y = NULL)

  p <- (p_time / p_mem) + plot_layout(guides = "collect") +
    plot_annotation(
      title = title,
      subtitle = "Under a 24 GB, 8 core cap. One repeat per run; a run that died shows where.",
      caption = paste(
        "Docker runs only; the native bixverse runs (CPU, wgpu, MLX) are in their own table in docs/results.md.",
        "Scanpy dask has no DGE step. A run that timed out in tSNE keeps its time without tSNE.",
        sep = "\n"
      ),
      theme = theme_bench(14)
    ) &
    scale_fill_manual(values = family_cols, name = NULL) &
    theme_bench(14) &
    theme(panel.grid.major.y = element_blank(), legend.position = "bottom")

  ggsave(file.path(fig_dir, paste0(file, ".png")), p, width = 14, height = 11, dpi = 300, bg = surface)
  ggsave(file.path(fig_dir, paste0(file, ".pdf")), p, width = 14, height = 11, bg = surface)
}

scaling_bars(
  c(splat_100k = "100k (96,342 cells)", splat_500k = "500k (482,409 cells)", splat_1m = "1M (964,763 cells)"),
  "Splat simulation: time and memory", "scaling_splat"
)
scaling_bars(size_labels, "Parse 1M PBMC: time and memory", "scaling_pbmc")

#### figure 2: per-step heatmap, each step scaled across frameworks -----------

# heatmap0 without its near-black first slot, which marks missing tiles instead
step_ramp <- c("#005F73", "#0A9396", "#94D2BD", "#E9D8A6", "#EE9B00", "#CA6702", "#AE2012", "#9B2226")
missing_fill <- "#001219"
no_step <- list(
  bixverse = "normalise",
  Scanpy = c("cluster_fast", "tsne_quick"),
  Seurat = c("cluster_fast", "tsne_quick"),
  scrapper = c("tsne_default", "tsne_fft"),
  CyteArc = c("cluster_fast", "tsne_default", "tsne_fft", "tsne_quick")
)
total_step <- "total (no tSNE)"
ratio_cap <- log2(32)

step_heatmap <- function(labels, title, file, height, width = 11, base_size = 10, text_size = 2.4) {
  d <- dt_all[size %in% names(labels)]
  d[, family := sub(" .*", "", column)]
  # a run that died in a tSNE step still has a total without tSNE
  tot <- d[, {
    died <- any(status != "ok" & !grepl("^tsne", step))
    .(
      step = total_step,
      seconds = if (died) NA_real_ else sum(seconds[!grepl("^tsne|^cluster_fast", step)], na.rm = TRUE),
      status = if (died) "failed" else "ok"
    )
  }, by = .(column, size, family)]
  d <- rbind(d[, .(column, size, family, step, seconds, status)], tot)
  grid <- unique(d[, .(column, size, family)])[, .(step = c(step_order, total_step)), by = .(column, size, family)]
  d <- merge(grid, d, by = c("column", "size", "family", "step"), all.x = TRUE)
  d[, lab := fcase(
    mapply(function(f, s) s %in% no_step[[f]], family, step), "n/a",
    !is.na(status) & status != "ok", sub(" ", "\n", status),
    is.na(seconds), "-",
    seconds < 10, sprintf("%.1f", seconds),
    default = format(round(seconds), big.mark = ",", trim = TRUE)
  )]
  d[!is.na(status) & status != "ok", seconds := NA_real_]
  # log2 ratio to the fastest run that finished the step, capped at 32x and put
  # on 0 to 1: unlike a min-max scale, 200 s against 201 s stays one colour.
  # Floored at 1 s, so sub-second steps and lazy (0 s) normalisation don't blow up the ratio
  d[, scaled := {
    s <- pmax(seconds, 1)
    pmin(log2(s / suppressWarnings(min(s, na.rm = TRUE))), ratio_cap) / ratio_cap
  }, by = .(size, step)]
  d <- d[, if (any(!is.na(seconds))) .SD, by = .(size, step)]
  d[, size_label := factor(labels[size], levels = labels)]
  d[, column := factor(column, levels = column_order)]
  d[, step := factor(step, levels = rev(c(step_order, total_step)))]
  d[, light := !is.na(scaled) & scaled > 0.2 & scaled < 0.6]

  p <- ggplot(d, aes(column, step)) +
    geom_tile(aes(fill = scaled), colour = surface, linewidth = 0.8) +
    geom_text(aes(label = lab, colour = light), size = text_size, lineheight = 0.85, show.legend = FALSE) +
    scale_fill_gradientn(
      colours = step_ramp, limits = c(0, 1), na.value = missing_fill,
      breaks = log2(c(1, 2, 4, 8, 16, 32)) / ratio_cap,
      labels = c("fastest", "2x", "4x", "8x", "16x", "32x+"), name = "against the fastest"
    ) +
    scale_colour_manual(values = c(`FALSE` = "#ffffff", `TRUE` = ink)) +
    facet_wrap(~size_label, ncol = 1, scales = "free_x") +
    labs(
      title = title,
      subtitle = "Seconds per step. Colour is the ratio to the fastest run that finished that step at that size (times under 1 s count as 1 s), capped at 32x.",
      caption = paste(
        "Black: n/a (step not in that framework), OOM or TIMEOUT where the run died, - not reached.",
        "Scanpy dask has no DGE step. Docker runs only; the native bixverse runs are in their own table.",
        "bixverse CPU tSNE builds its kNN with IVF from 500k (kmknn at 100k). (qd) steps are not in the total.",
        sep = "\n"
      ),
      x = NULL, y = NULL
    ) +
    theme_bench(base_size) +
    theme(
      panel.grid.major = element_blank(),
      axis.text.x = element_text(angle = 35, hjust = 1),
      legend.key.width = unit(1.6, "cm")
    )
  # the size is in the title already
  if (length(labels) == 1) p <- p + theme(strip.text = element_blank())

  ggsave(file.path(fig_dir, paste0(file, ".png")), p, width = width, height = height, dpi = 300, bg = surface)
  ggsave(file.path(fig_dir, paste0(file, ".pdf")), p, width = width, height = height, bg = surface)
}

step_heatmap(
  c(splat_100k = "100k (96,342 cells)", splat_500k = "500k (482,409 cells)", splat_1m = "1M (964,763 cells)"),
  "Wall time per step: Splat simulation", "steps_heatmap_splat", 16
)
step_heatmap(size_labels, "Wall time per step: Parse 1M PBMC", "steps_heatmap_pbmc", 16)

# one figure per size, larger type
for (lst in list(
  list(c(splat_100k = "100k (96,342 cells)", splat_500k = "500k (482,409 cells)", splat_1m = "1M (964,763 cells)"),
       "Splat simulation", "splat"),
  list(size_labels, "Parse 1M PBMC", "pbmc")
)) {
  for (k in names(lst[[1]])) {
    step_heatmap(
      lst[[1]][k], paste0("Wall time per step: ", lst[[2]], ", ", lst[[1]][k]),
      paste0("steps_heatmap_", lst[[3]], "_", sub(".*_", "", k)),
      height = 9.5, width = 13, base_size = 14, text_size = 3.6
    )
  }
}

#### figure 3: speed-up per step against a Scanpy reference ------------------

# normalisation is deferred in Dask, scrapper (normalizeCounts(delayed = TRUE)) and CyteArc:
# the cost lands in later steps, so a fold change against or of it is meaningless
lazy_cols <- c("Scanpy dask", "scrapper h5ad", "scrapper HDF5", "CyteArc mtx", "CyteArc h5ad")

speedup_plot <- function(size_key, ref_col, title, subtitle, caption, file, height) {
  d <- dt[size == size_key & status == "ok"]
  survivors <- runs[size == size_key & status == "ok" & column != ref_col, as.character(column)]
  tot <- runs[size == size_key & status == "ok", .(column, step = "total (no tSNE)", seconds = no_tsne)]
  fc <- rbind(d[, .(column, step = as.character(step), seconds)], tot)
  ref <- fc[column == ref_col, .(step, ref_s = seconds)]
  fc <- merge(fc[column %in% survivors], ref, by = "step")
  fc[, fold := ref_s / seconds]
  fc[, lazy := step == "normalise" & (column %in% lazy_cols | ref_col %in% lazy_cols)]
  fc[lazy == TRUE, fold := NA_real_]
  fc[, step := factor(step, levels = c(step_order, "total (no tSNE)"))]
  fc[, column := factor(column, levels = rev(column_order))]
  fc[, lab := fcase(
    lazy, "lazy",
    fold >= 10, sprintf("%.0fx", fold),
    fold < 0.1, sprintf("%.2fx", fold),
    default = sprintf("%.1fx", fold)
  )]
  lim <- log2(32)

  p <- ggplot(fc, aes(step, column)) +
    geom_tile(aes(fill = pmax(pmin(log2(fold), lim), -lim)), colour = surface, linewidth = 0.8) +
    geom_text(
      aes(label = lab, colour = is.na(fold) | log2(fold) < -2 | log2(fold) > 2.7),
      size = 3.6, show.legend = FALSE
    ) +
    scale_colour_manual(values = c(`FALSE` = ink, `TRUE` = "#ffffff")) +
    # the heatmap ramp reversed, beige pinned to "same"
    scale_fill_gradientn(
      colours = rev(step_ramp), values = c(0, 0.125, 0.25, 0.375, 0.5, 2 / 3, 5 / 6, 1),
      na.value = missing_fill,
      limits = c(-lim, lim),
      breaks = log2(c(1 / 16, 1 / 4, 1, 4, 16)),
      labels = c("16x slower", "4x slower", "same", "4x faster", "16x faster"),
      name = NULL
    ) +
    labs(title = title, subtitle = subtitle, caption = caption, x = NULL, y = NULL) +
    theme_bench(14) +
    theme(
      panel.grid.major = element_blank(),
      axis.text.x = element_text(angle = 35, hjust = 1),
      legend.key.width = unit(2.2, "cm")
    )

  ggsave(file.path(fig_dir, paste0(file, ".png")), p, width = 13, height = height, dpi = 300, bg = surface)
  ggsave(file.path(fig_dir, paste0(file, ".pdf")), p, width = 13, height = height, bg = surface)
}

speedup_plot(
  "parse_500k", "Scanpy h5ad",
  title = "Speed-up per step against in-memory Scanpy (h5ad), 500k",
  subtitle = "The largest size in-memory Scanpy survives. Only runs that completed at 500k.",
  caption = paste(
    "bixverse normalises during load. Scanpy dask has no DGE step. bixverse CPU tSNE builds its kNN with IVF.",
    "tsne_quick (qdtsne) and cluster_fast (Leiden on k-means centroids) are not shown and not in the total.",
    sep = "\n"
  ),
  file = "speedup_vs_scanpy_500k",
  height = 5.6
)

speedup_plot(
  "parse_full", "Scanpy dask",
  title = "Speed-up per step against Scanpy with Dask, full data set",
  subtitle = "In-memory Scanpy dies at load here; Dask is the Scanpy path that finishes. Only runs that completed.",
  caption = paste(
    "bixverse normalises during load; Dask defers normalisation, so the normalise column carries no fold change.",
    "Dask has no DGE step (Wilcoxon fails on Dask arrays), so its total lacks one; in-memory Scanpy's takes 602 s at 500k.",
    "bixverse CPU tSNE builds its kNN with IVF.",
    sep = "\n"
  ),
  file = "speedup_vs_scanpy_dask_full",
  height = 4.6
)

#### figure 4: cold vs warm load ------------------------------------------------

# warm_long.csv: uv run scripts/tables.py --warm results > docs/figures/warm_long.csv
wl <- fread(file.path(fig_dir, "warm_long.csv"))
wl[, size_label := factor(size_labels[size], levels = size_labels)]
wl[, start := factor(start, levels = c("cold", "warm"))]
wl[, family := sub(" .*", "", framework)]

fig4 <- ggplot(wl, aes(size_label, seconds, fill = start)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.75) +
  geom_text(
    aes(label = sprintf(ifelse(seconds < 10, "%.1f s", "%.0f s"), seconds)),
    position = position_dodge(width = 0.8), vjust = -0.4, size = 2.8, colour = ink
  ) +
  facet_wrap(~framework) +
  scale_fill_manual(values = c(cold = step_ramp[3], warm = step_ramp[1]), name = NULL) +
  scale_y_continuous(
    labels = scales::label_number(suffix = " s"),
    expand = expansion(mult = c(0, 0.1))
  ) +
  labs(
    title = "Load: cold conversion against a warm reconnect",
    subtitle = "Warm reopens what the cold run wrote to disk. One repeat each, run straight after the cold run.",
    caption = "Cold load from mtx. BPCells warm reopens the pre-filtered, pre-QC matrix; CyteArc warm reopens its store.",
    x = NULL, y = NULL
  ) +
  theme_bench() +
  theme(panel.grid.major.x = element_blank())

ggsave(file.path(fig_dir, "warm_start.png"), fig4, width = 11, height = 3.6, dpi = 300, bg = surface)
ggsave(file.path(fig_dir, "warm_start.pdf"), fig4, width = 11, height = 3.6, bg = surface)

#### figure 5: native GPU against native CPU ------------------------------------

# native_long.csv: uv run scripts/tables.py --native-long results > docs/figures/native_long.csv
nl <- fread(file.path(fig_dir, "native_long.csv"))
native_sizes <- c(
  splat_100k = "Splat 100k", parse_100k = "PBMC 100k",
  splat_500k = "Splat 500k", parse_500k = "PBMC 500k",
  splat_1m = "Splat 1M", parse_full = "PBMC full"
)
# the same CPU code in every row: load, QC, HVG, Leiden, DGE and the Barnes-Hut optimiser
cpu_steps <- c("load", "qc", "hvg", "cluster", "dge", "tsne_default")
native_cols <- c(step_order[step_order != "normalise"], "total (no tSNE)", "peak footprint")
native_lab <- setNames(
  fifelse(native_cols %in% cpu_steps, paste(native_cols, "(CPU)"), native_cols),
  native_cols
)

tot <- nl[, .(step = "total (no tSNE)", seconds = sum(seconds[!grepl("^tsne|^cluster_fast", step)])), by = .(column, size)]
fc <- rbind(nl[, .(column, size, step, seconds)], tot)
fc <- merge(
  fc[column != "native CPU"],
  fc[column == "native CPU", .(size, step, ref_s = seconds)],
  by = c("size", "step")
)
fc[, fold := ref_s / seconds]
fc[, lab := sprintf(ifelse(fold >= 10, "%.0fx", "%.1fx"), fold)]
# memory: the label is GPU over CPU footprint; colour as the speed-up, so more memory reads as slower
mem <- unique(nl[, .(column, size, peak_gb)])
mem <- merge(mem[column != "native CPU"], mem[column == "native CPU", .(size, ref_gb = peak_gb)], by = "size")
fc <- rbind(fc[, .(column, size, step, fold, lab)],
            mem[, .(column, size, step = "peak footprint", fold = ref_gb / peak_gb, lab = sprintf("%.1fx", peak_gb / ref_gb))])
fc[, cpu_only := step %in% cpu_steps]
fc[, step := factor(native_lab[step], levels = native_lab)]
fc[, column := factor(sub("native ", "", column), levels = c("MLX", "wgpu"))]
fc[, size_label := factor(native_sizes[size], levels = native_sizes)]
lim <- log2(32)
fc[, text_col := fcase(cpu_only, "cpu", abs(log2(fold)) > 2, "light", default = "dark")]

fig5 <- ggplot(fc, aes(step, column)) +
  geom_tile(aes(fill = pmax(pmin(log2(fold), lim), -lim)), colour = surface, linewidth = 0.8) +
  geom_text(aes(label = lab, colour = text_col), size = 3.4, show.legend = FALSE) +
  scale_colour_manual(values = c(dark = ink, light = "#ffffff", cpu = ink_2)) +
  scale_fill_gradientn(
    colours = rev(step_ramp), values = c(0, 0.125, 0.25, 0.375, 0.5, 2 / 3, 5 / 6, 1),
    limits = c(-lim, lim),
    breaks = log2(c(1 / 16, 1 / 4, 1, 4, 16)),
    labels = c("16x slower", "4x slower", "same", "4x faster", "16x faster"),
    name = NULL
  ) +
  facet_wrap(~size_label, ncol = 2) +
  labs(
    title = "Native GPU against native CPU, per step",
    subtitle = "Speed-up of bixverse.gpu (wgpu, MLX) over the same bixverse pipeline on the CPU, both native on macOS. One repeat each.",
    caption = paste(
      "(CPU): the same CPU code in every row, so these tiles show run-to-run noise. Default tSNE runs the Barnes-Hut optimiser on the CPU.",
      "Peak footprint: GPU over CPU peak (macOS /usr/bin/time -l, whole run), coloured red when the GPU row needs more.",
      "(qd) steps tsne_quick and cluster_fast are not in the total. M1 Max, 8 threads, R 4.6.1.",
      sep = "\n"
    ),
    x = NULL, y = NULL
  ) +
  theme_bench(12) +
  theme(
    panel.grid.major = element_blank(),
    axis.text.x = element_text(angle = 40, hjust = 1),
    legend.key.width = unit(2.2, "cm")
  )

ggsave(file.path(fig_dir, "native_gpu_speedup.png"), fig5, width = 16, height = 8, dpi = 300, bg = surface)
ggsave(file.path(fig_dir, "native_gpu_speedup.pdf"), fig5, width = 16, height = 8, bg = surface)

#### figure 6: native time and memory per size ----------------------------------

native_cols_fill <- c(`native CPU` = "#0F8096", `native wgpu` = "#EE9B00", `native MLX` = "#AE2012")
nr <- nl[, .(
  no_tsne = sum(seconds[!grepl("^tsne|^cluster_fast", step)]),
  peak_gb = peak_gb[1]
), by = .(column, size)]
nr[, size_label := factor(native_sizes[size], levels = native_sizes[c(1, 3, 5, 2, 4, 6)])]
nr[, column := factor(column, levels = rev(names(native_cols_fill)))]

native_bars <- function(x, lab, title) {
  ggplot(nr, aes(y = column)) +
    geom_col(aes(x = .data[[x]], fill = column), width = 0.75) +
    geom_text(aes(x = .data[[x]], label = lab(.data[[x]])), hjust = -0.15, size = 3.6, colour = ink) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.3))) +
    facet_wrap(~size_label, nrow = 1, scales = "free_x") +
    labs(title = title, x = NULL, y = NULL)
}

fig6 <- (native_bars("no_tsne", function(v) sprintf("%.0f s", v), "Without tSNE (s)") /
  native_bars("peak_gb", function(v) sprintf("%.1f", v), "Peak footprint (GB)")) +
  plot_layout(guides = "collect") +
  plot_annotation(
    title = "Native bixverse: CPU against GPU, time and memory",
    subtitle = "Same pipeline and parameters, native on macOS (M1 Max, 8 threads, R 4.6.1). One repeat per run.",
    caption = paste(
      "Peak footprint from /usr/bin/time -l over the whole run, tSNE included; no memory cap, so it does not compare with the Docker figures.",
      "At splat 100k the GPU rows' extra memory is CPU heap that grows in the tSNE steps, not GPU buffers; why it is not released is not checked.",
      sep = "\n"
    ),
    theme = theme_bench(14)
  ) &
  scale_fill_manual(values = native_cols_fill, breaks = names(native_cols_fill), name = NULL) &
  theme_bench(14) &
  theme(panel.grid.major.y = element_blank(), legend.position = "bottom")

ggsave(file.path(fig_dir, "native_scaling.png"), fig6, width = 16, height = 8, dpi = 300, bg = surface)
ggsave(file.path(fig_dir, "native_scaling.pdf"), fig6, width = 16, height = 8, bg = surface)
