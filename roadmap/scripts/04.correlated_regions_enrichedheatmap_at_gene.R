library(methods)

suppressPackageStartupMessages(library(GetoptLong))
on = "tss"
type = "neg"
K = 1
cutoff = 0.01
meandiff = 0.3
rerun = FALSE
GetoptLong("on=s", "tss|body",
	       "type=s", "neg|pos",
	       "K=i", "1,2,3,4",
	       "cutoff=f", "0.05",
	       "meandiff=f", "0",
	       "rerun!", "rerun")

BASE_DIR = "/icgc/dkfzlsdf/analysis/B080/guz/roadmap_analysis/re_analysis"
source(qq("@{BASE_DIR}/scripts/configure/roadmap_configure.R"))

km = readRDS(qq("@{OUTPUT_DIR}/rds/mat_all_cr_enriched_to_gene_extend_50000_target_0.33_row_order_km3_and_km4.rds"))[[2]]
km_col = structure(brewer.pal(9, "Set1")[c(3,4,5,1)], names = c(1:4))

neg_cr_all = readRDS(qq("@{OUTPUT_DIR}/rds/all_neg_cr_w6s3.rds"))
pos_cr_all = readRDS(qq("@{OUTPUT_DIR}/rds/all_pos_cr_w6s3.rds"))
cr_all = c(neg_cr_all, pos_cr_all)
cr_all = copy_cr_attribute(neg_cr_all, cr_all)

### read significant CRs
if(on == "tss") {
	if(type == "neg") {
		cr = readRDS(qq("@{OUTPUT_DIR}/rds/all_neg_cr_w6s3_fdr_less_than_@{cutoff}_methdiff_larger_than_@{meandiff}.rds"))
		cr_vice = readRDS(qq("@{OUTPUT_DIR}/rds/all_pos_cr_w6s3_fdr_less_than_@{cutoff}_methdiff_larger_than_@{meandiff}.rds"))
	} else if(type == "pos") {
		cr = readRDS(qq("@{OUTPUT_DIR}/rds/all_pos_cr_w6s3_fdr_less_than_@{cutoff}_methdiff_larger_than_@{meandiff}.rds"))
		cr_vice = readRDS(qq("@{OUTPUT_DIR}/rds/all_neg_cr_w6s3_fdr_less_than_@{cutoff}_methdiff_larger_than_@{meandiff}.rds"))
	}
} else {
	neg_cr = readRDS(qq("@{OUTPUT_DIR}/rds/all_neg_cr_w6s3.rds"))
	pos_cr = readRDS(qq("@{OUTPUT_DIR}/rds/all_pos_cr_w6s3.rds"))
	cr = c(neg_cr, pos_cr)
	cr = copy_cr_attribute(neg_cr, cr)

	gi = names(km[km == K])
	cr = cr[cr$gene_id %in% gi]
}


sample_id = attr(cr, "sample_id")
	
gene = genes(TXDB)
gene = gene[intersect(names(gene), names(km))]

# get target regions
if(on == "tss") {
	qqcat("extracting gene tss\n")
	tss = promoters(gene, upstream = 1, downstream = 0)
	tss = tss[names(tss) %in% cr$gene_id]
	mapping_column = "gene_id"

	target = tss
	target_ratio = 0.1
	axis_name = c("-5KB", "TSS", "5KB")
} else {
	qqcat("extracting gene body\n")
	gene = gene[names(gene) %in% cr$gene_id]

	target = gene
	target_ratio = 0.6
	mapping_column = "gene_id"
	axis_name = c("-5KB", "TSS", "TES", "5KB")
}

target = sort(target)

# normalize cr to targets
if(on == "tss") {
	extend = c(5000, 10000)
	mat = normalizeToMatrix(cr, target, mapping_column = mapping_column,
		        extend = extend, mean_mode = "absolute", w = 50, target_ratio = target_ratio, trim = 0)
	if(type == "neg") {
		mat[mat == 1] = -1
	}
	mat_vice = normalizeToMatrix(cr_vice, target, mapping_column = mapping_column,
		        extend = extend, mean_mode = "absolute", w = 50, target_ratio = target_ratio, trim = 0)
	if(type == "pos") {
		mat_vice[mat_vice == 1] = -1
	}
} else {
	extend = 5000
	mat = normalizeToMatrix(cr, target, mapping_column = mapping_column, value_column = "corr",
	        extend = extend, mean_mode = "absolute", w = 50, target_ratio = target_ratio, trim = 0, empty_value = 0)
	mat_corr = mat
}

# in case no significant CR in the tss area
if(on == "tss") {
	l = rowSums(abs(mat)) > 0
	mat = mat[l, ]
	mat_vice = mat_vice[l, ]
	target = target[l]
	qqcat("@{sum(!l)}/@{length(l)} targets are filtered because there is no CR overlaped.\n")

	mat_corr = normalizeToMatrix(cr_all, target, mapping_column = mapping_column, value_column = "corr",
	        extend = extend, mean_mode = "absolute", w = 50, target_ratio = target_ratio, trim = 0, empty_value = 0)
}

if(on == "tss") {
	target_tss = promoters(target, upstream = 1, downstream = 0)
	mat_tss = normalizeToMatrix(target_tss, target,
			        extend = extend, mean_mode = "absolute", w = 50, target_ratio = target_ratio, trim = 0)

	# l = rowSums(mat_tss) == 1
	# mat = mat[l, ]
	# target = target[l]
	# qqcat("@{sum(!l)}/@{length(l)} targets are filtered because there are more than one tss.\n")

}

km = km[names(target)]

# normalize to CGI
mat_cgi = normalizeToMatrix(CGI, target,
        extend = extend, mean_mode = "absolute", w = 50, target_ratio = target_ratio)

sample_id_subgroup1 = intersect(sample_id, rownames(SAMPLE[SAMPLE$subgroup == "subgroup1", ]))
sample_id_subgroup2 = intersect(sample_id, rownames(SAMPLE[SAMPLE$subgroup == "subgroup2", ]))

if(on == "tss") {
	rdata_file = qq("@{OUTPUT_DIR}/rds/cr_enrichedheatmap_on_@{on}_by_gene_@{type}_fdr_@{cutoff}_methdiff_@{meandiff}.RData")
} else {
	rdata_file = qq("@{OUTPUT_DIR}/rds/cr_enrichedheatmap_on_@{on}_km_@{K}.RData")
}
if(file.exists(rdata_file) && !rerun) {
	load(rdata_file)
} else {
	# normalize to methylation
	meth_mat = enrich_with_methylation(target, sample_id, target_ratio = target_ratio, extend = extend)
	failed_rows = attr(meth_mat, "failed_rows")
	qqcat("There are @{length(failed_rows)} failed rows when normalizing methylation to the targets.\n")
	meth_mat[failed_rows, ] = 0.5

	meth_mat_1 = enrich_with_methylation(target, sample_id_subgroup1, target_ratio = target_ratio, extend = extend)
	failed_rows = attr(meth_mat_1, "failed_rows")
	qqcat("There are @{length(failed_rows)} failed rows when normalizing methylation to the targets.\n")
	meth_mat_1[failed_rows, ] = 0.5

	meth_mat_2 = enrich_with_methylation(target, sample_id_subgroup2, target_ratio = target_ratio, extend = extend)
	failed_rows = attr(meth_mat_2, "failed_rows")
	qqcat("There are @{length(failed_rows)} failed rows when normalizing methylation to the targets.\n")
	meth_mat_2[failed_rows, ] = 0.5

	meth_mat_diff = meth_mat_1 - meth_mat_2

	cor_mat_list = list()
	hist_mat_list = list()
	hist_mat_list_subgroup1 = list()
	hist_mat_list_subgroup2 = list()
	hist_mat_list_diff = list()

	
	for(k in seq_along(MARKS)) {
		hm_sample = intersect(sample_id, chipseq_hooks$sample_id(MARKS[k]))
		# applied to each sample, each mark
		lt = enrich_with_histone_mark(target, sample_id = sample_id, mark = MARKS[k], return_arr = TRUE, target_ratio = target_ratio, extend = extend)
		arr = lt[[1]]

		# only calculate the correlation when there are enough samples
		if(length(hm_sample) >= 5) {
			# detect regions that histone MARKS correlate to expression
			expr2 = EXPR[target$gene_id, intersect(colnames(EXPR), hm_sample)]
			cor_mat = matrix(nrow = nrow(expr2), ncol = ncol(mat))
			cor_p_mat = cor_mat

			counter = set_counter(nrow(cor_mat))
			for(i in seq_len(nrow(cor_mat))) {
				counter()
			    for(j in seq_len(ncol(cor_mat))) {
			        x = cor(arr[i, j, ], expr2[i, ], method = "spearman")
			        cor_mat[i, j] = x
			        # cor_p_mat[i, j] = cor.test(arr[i, j, ], expr2[i, ], method = "spearman")$p.value
			    }
			}
			cat("\n")
			cor_mat[is.na(cor_mat)] = 0
			# cor_fdr_mat = p.adjust(cor_p_mat, method = "BH")
			# l1 = cor_fdr_mat < 0.1 & cor_mat > 0
			# cor_mat[l1] = 1
			# l2 = cor_fdr_mat < 0.1 & cor_mat < 0
			# cor_mat[l2] = -1 
			# cor_mat[!(l1 | l2)] = 0
			cor_mat = copyAttr(mat, cor_mat)
			cor_mat_list[[k]] = cor_mat

			if(sum(abs(cor_mat)) == 0) {
				cor_mat_list[[k]] = NA
			}
		} else {
			cor_mat_list[[k]] = NA
		}
		hist_mat_list[[k]] = lt[[2]]
		hist_mat_list_subgroup1[[k]] = apply(arr[, , intersect(hm_sample, sample_id_subgroup1)], c(1, 2), mean, na.rm = TRUE)
		hist_mat_list_subgroup1[[k]] = copyAttr(mat, hist_mat_list_subgroup1[[k]])
		hist_mat_list_subgroup2[[k]] = apply(arr[, , intersect(hm_sample, sample_id_subgroup2)], c(1, 2), mean, na.rm = TRUE)
		hist_mat_list_subgroup2[[k]] = copyAttr(mat, hist_mat_list_subgroup2[[k]])

		hist_mat_list_diff[[k]] = hist_mat_list_subgroup1[[k]] - hist_mat_list_subgroup2[[k]]
	}


	save(meth_mat, meth_mat_1, meth_mat_2, meth_mat_diff, cor_mat_list, 
		hist_mat_list, hist_mat_list_subgroup1, hist_mat_list_subgroup2, hist_mat_list_diff, file = rdata_file)
}

expr = EXPR[target$gene_id, sample_id, drop = FALSE]

## gene length
gl = width(gene[target$gene_id])

if(on == "body") {
	col = colorRamp2(c(-1,0,1), c("darkgreen", "white", "red"))
} else {
	col = c("-1" = "darkgreen", "0" = "white", "1" = "red")
}


n_heatmap = 0
if(on != "tss") {
	n_row_cluster = 3
} else {
	n_row_cluster = 2
}

qqcat("making heatmap...\n")


add_boxplot_of_gene_length = function(ht_list) {
	cat("add boxplot\n")
	gl = gl
	anno_name = "gene_len"
	
	row_order_list = row_order(ht_list)
	lt = lapply(row_order_list, function(ind) gl[ind])
	bx = boxplot(lt, plot = FALSE)$stats
	n = length(row_order_list)
	x_ind = (seq_len(n) - 0.5)/n
	w = 1/n*0.5
	decorate_annotation(anno_name, slice = 1, {
		rg = range(bx)
		rg[1] = rg[1] - (rg[2] - rg[1])*0.1
		rg[2] = rg[2] + (rg[2] - rg[1])*0.1
		pushViewport(viewport(y = unit(1, "npc") + unit(1, "mm"), just = "bottom", height = unit(2, "cm"), yscale = rg))
		grid.rect(gp = gpar(col = "black"))
		grid.segments(x_ind - w/2, bx[5, ], x_ind + w/2, bx[5, ], default.units = "native", gp = gpar(lty = 1:n))
		grid.segments(x_ind - w/2, bx[1, ], x_ind + w/2, bx[1, ], default.units = "native", gp = gpar(lty = 1:n))
		grid.segments(x_ind, bx[1, ], x_ind, bx[5, ], default.units = "native", gp = gpar(lty = 1:n))
		grid.rect(x_ind, colMeans(bx[c(4, 2), ]), width = w, height = bx[4, ] - bx[2, ], default.units = "native", gp = gpar(fill = "white", lty = 1:n))
		grid.segments(x_ind - w/2, bx[3, ], x_ind + w/2, bx[3, ], default.units = "native", gp = gpar(lty = 1:n))
		grid.yaxis(main = FALSE, gp = gpar(fontsize = 8))
		grid.text(anno_name, y = unit(1, "npc") + unit(2.5, "mm"), gp = gpar(fontsize = 14), just = "bottom")
		upViewport()
	})
}

add_prop = function(ht_list) {
	cat("add prop\n")
	ht_name = "km_groups"
	
	row_order_list = row_order(ht_list)
	lt = lapply(row_order_list, function(ind) table(km[ind])/length(ind))
	lt = lapply(lt, function(x) x[order(names(x))])
	n = length(row_order_list)
	x_ind = (seq_len(n) - 0.5)/n
	w = 1/n*0.8
	decorate_heatmap_body(ht_name, slice = 1, {
		rg = c(0, 1)
		pushViewport(viewport(y = unit(1, "npc") + unit(1, "mm"), just = "bottom", height = unit(2, "cm"), yscale = rg))
		for(i in seq_along(lt)) {
			y = lt[[i]]
			grid.rect(x_ind[i], cumsum(y), width = w, height = y, just = c("center", "top"), gp = gpar(fill = km_col[names(y)], lty = i))
		}
		upViewport()
	})
}


## calculate row orders
expr_mean = rowMeans(expr[, SAMPLE[sample_id, ]$subgroup == "subgroup1"]) - 
			rowMeans(expr[, SAMPLE[sample_id, ]$subgroup == "subgroup2"])
expr_split = ifelse(expr_mean > 0, "high", "low")
expr_split = factor(expr_split, levels = c("high", "low"))

set.seed(123)
if(on == "tss") {
	# find another way to split by methylation
	upstream_index = length(attr(meth_mat, "upstream_index"))
	meth_split = kmeans(meth_mat[, seq(round(upstream_index*0.8), round(upstream_index*7/5))], centers = 2)$cluster
	x = tapply(rowMeans(meth_mat[, seq(round(upstream_index*0.8), round(upstream_index*7/5))]), meth_split, mean)
	od = structure(order(x), names = names(x))
	meth_split = paste0("cluster", od[as.character(meth_split)])
} else {
	upstream_index = length(attr(meth_mat, "upstream_index"))
	meth_split = kmeans(meth_mat[, seq(round(upstream_index*0.8), round(upstream_index*1.2))], centers = 3)$cluster
	x = tapply(rowMeans(meth_mat[, seq(round(upstream_index*0.8), round(upstream_index*7/5))]), meth_split, mean)
	od = structure(order(x), names = names(x))
	meth_split = paste0("cluster", od[as.character(meth_split)])
}
combined_split = paste(meth_split, expr_split, sep = "|")

merge_row_order = function(l_list) {
	do.call("c", lapply(l_list, function(l) {
		if(sum(l) == 0) return(integer(0))
		if(sum(l) == 1) return(which(l))
		dend1 = as.dendrogram(hclust(dist_by_closeness2(mat[l, ])))
		dend1 = reorder(dend1, rowMeans(mat[l, ]))
		od = order.dendrogram(dend1)
		which(l)[od]
	}))
}

if(on == "tss") {
	row_order = merge_row_order(list(
		combined_split == "cluster1|high" & km == 1,
		combined_split == "cluster1|high" & km == 2,
		combined_split == "cluster1|high" & km == 3,
		combined_split == "cluster1|high" & km == 4,
		combined_split == "cluster1|low" & km == 1,
		combined_split == "cluster1|low" & km == 2,
		combined_split == "cluster1|low" & km == 3,
		combined_split == "cluster1|low" & km == 4,
		combined_split == "cluster2|high" & km == 1,
		combined_split == "cluster2|high" & km == 2,
		combined_split == "cluster2|high" & km == 3,
		combined_split == "cluster2|high" & km == 4,
		combined_split == "cluster2|low" & km == 1,
		combined_split == "cluster2|low" & km == 2,
		combined_split == "cluster2|low" & km == 3,
		combined_split == "cluster2|low" & km == 4
	))
} else {
	row_order = merge_row_order(list(
		combined_split == "cluster1|high",
		combined_split == "cluster1|low",
		combined_split == "cluster2|high",
		combined_split == "cluster2|low",
		combined_split == "cluster3|high",
		combined_split == "cluster3|low"
	))
}

## heatmap for expression
# columns are clustered for each subgroup
dend1 = as.dendrogram(hclust(dist(t(expr[, SAMPLE$subgroup == "subgroup1"]))))
hc1 = as.hclust(reorder(dend1, colMeans(expr[, SAMPLE$subgroup == "subgroup1"])))
expr_col_od1 = hc1$order
dend2 = as.dendrogram(hclust(dist(t(expr[, SAMPLE$subgroup == "subgroup2"]))))
hc2 = as.hclust(reorder(dend2, colMeans(expr[, SAMPLE$subgroup == "subgroup2"])))
expr_col_od2 = hc2$order
expr_col_od = c(which(SAMPLE$subgroup == "subgroup1")[expr_col_od1], which(SAMPLE$subgroup == "subgroup2")[expr_col_od2])

cor_col_fun = colorRamp2(c(-1, 0, 1), c("darkgreen", "white", "red"))

ht_list = Heatmap(expr, name = "expr", show_row_names = FALSE,
	show_column_names = FALSE, width = unit(5, "cm"), show_column_dend = FALSE, cluster_columns = FALSE, column_order = expr_col_od,
	top_annotation = HeatmapAnnotation(group = SAMPLE[sample_id, ]$group, sample_type = SAMPLE[sample_id, ]$sample_type, subgroup = SAMPLE[sample_id, ]$subgroup, 
		col = list(group = COLOR$group, sample_type = COLOR$sample_type, subgroup = COLOR$subgroup), show_annotation_name = TRUE, annotation_name_side = "left"),
	column_title = "Expression", show_row_dend = FALSE,
	use_raster = TRUE, raster_quality = 2)
gap = unit(1, "cm")
n_heatmap = n_heatmap + 1



## gene length
gl[gl > quantile(gl, 0.95)] = quantile(gl, 0.95)
ht_list = ht_list + rowAnnotation(gene_len = row_anno_points(gl, axis = TRUE, gp = gpar(col = "#00000040")), width = unit(1, "cm"))
gap = unit.c(gap, unit(1, "cm"))

# annotate to the "four groups"
ht_list = ht_list + Heatmap(km[names(target)], name = "km_groups", col = km_col, show_row_names = FALSE,
	width = unit(1, "cm"))

gap = unit.c(gap, unit(1, "cm"))

## enrichment to CGI
ht_list = ht_list + EnrichedHeatmap(mat_cgi, col = c("white", "darkorange"), name = "CGI",
	  top_annotation = HeatmapAnnotation(lines1 = anno_enriched(gp = gpar(col = "darkorange", lty = 1:n_row_cluster))), 
	  top_annotation_height = unit(2, "cm"), column_title = "CGI", axis_name = axis_name,
	  use_raster = TRUE, raster_quality = 2) 
gap = unit.c(gap, unit(1, "cm"))  
n_heatmap = n_heatmap + 1

if(on == "tss") {
	mat_mix = mat
	mat_mix[mat == 0] = mat_vice[mat == 0]
	ht_list = ht_list + EnrichedHeatmap(mat_mix, col = col, 
				  name = qq("@{type}CR"),
	              top_annotation = HeatmapAnnotation(lines1 = anno_enriched(gp = gpar(pos_col = "red", neg_col = "darkgreen", lty = 1:n_row_cluster))), 
	              top_annotation_height = unit(2, "cm"), column_title = qq("@{type}CR"), axis_name = axis_name,
	              use_raster = TRUE, raster_quality = 2)
	gap = unit.c(gap, unit(1, "cm"))  
	n_heatmap = n_heatmap + 1
}

ht_list = ht_list + EnrichedHeatmap(mat_corr, col = cor_col_fun, name = qq("correlation"), 
      top_annotation = HeatmapAnnotation(lines1 = anno_enriched(gp = gpar(pos_col = "red", neg_col = "darkgreen", lty = 1:n_row_cluster))), 
      top_annotation_height = unit(2, "cm"), column_title = qq("corr_meth"), axis_name = axis_name,
      use_raster = TRUE, raster_quality = 2)
gap = unit.c(gap, unit(1, "cm"))
n_heatmap = n_heatmap + 1

# methylation
ht_list = ht_list + EnrichedHeatmap(meth_mat, col = colorRamp2(c(0, 0.5, 1), c("blue", "white", "red")), 
	name = "methylation", column_title = qq("meth"), axis_name = axis_name,
		heatmap_legend_param = list(title = "methylation"),
		top_annotation = HeatmapAnnotation(lines1 = anno_enriched(gp = gpar(col = "red", lty = 1:n_row_cluster))),
		use_raster = TRUE, raster_quality = 2)
gap = unit.c(gap, unit(1, "cm"))
n_heatmap = n_heatmap + 1

generate_diff_color_fun = function(x) {
	q = quantile(x, c(0.05, 0.95))
	max_q = max(abs(q))
	colorRamp2(c(-max_q, 0, max_q), c("#3794bf", "#FFFFFF", "#df8640"))
}

ht_list = ht_list + EnrichedHeatmap(meth_mat_diff, col = generate_diff_color_fun(meth_mat_diff),
	name = "methylation_diff", column_title = qq("meth_diff"), axis_name = axis_name,
		heatmap_legend_param = list(title = "methylation_diff"),
		top_annotation = HeatmapAnnotation(lines1 = anno_enriched(gp = gpar(pos_col = "#df8640", neg_col = "#3794bf", lty = 1:n_row_cluster))),
		use_raster = TRUE, raster_quality = 2)
gap = unit.c(gap, unit(1, "cm"))
n_heatmap = n_heatmap + 1

ht_list2 = NULL
ht_list1 = NULL
# correlation to histone marks
for(i in seq_along(cor_mat_list)) {
	if(i == 3) {
		ht_list1 = ht_list
		ht_list = NULL
	}
	if(length(cor_mat_list[[i]]) > 1) {
		anno_line_col = ifelse(mean(cor_mat_list[[i]], na.rm = TRUE) > 0, "red", "darkgreen")
		ht_list = ht_list + EnrichedHeatmap(cor_mat_list[[i]], col = cor_col_fun, name = qq("corr_@{MARKS[i]}"), 
	          top_annotation = HeatmapAnnotation(lines1 = anno_enriched(gp = gpar(pos_col = "red", neg_col = "darkgreen", lty = 1:n_row_cluster))), 
              top_annotation_height = unit(2, "cm"), column_title = qq("corr_@{MARKS[i]}"), axis_name = axis_name,
              use_raster = TRUE, raster_quality = 2)
	    gap = unit.c(gap, unit(1, "cm"))
   	 	n_heatmap = n_heatmap + 1
   	 }

    ht_list = ht_list + EnrichedHeatmap(hist_mat_list[[i]], col = colorRamp2(quantile(hist_mat_list[[i]], c(0, 0.95)), c("white", "purple")), name = qq("@{MARKS[i]}_1"),
		column_title = qq("@{MARKS[i]}"), axis_name = axis_name,
		heatmap_legend_param = list(title = qq("@{MARKS[i]}_density")),
		top_annotation = HeatmapAnnotation(lines1 = anno_enriched(gp = gpar(col = "purple", lty = 1:n_row_cluster))),
		use_raster = TRUE, raster_quality = 2)
	gap = unit.c(gap, unit(1, "cm"))
	n_heatmap = n_heatmap + 1

	ht_list = ht_list + EnrichedHeatmap(hist_mat_list_diff[[i]], name = qq("@{MARKS[i]}_diff"), col = generate_diff_color_fun(hist_mat_list_diff[[i]]),
		column_title = qq("@{MARKS[i]}_diff"), axis_name = axis_name,
		heatmap_legend_param = list(title = qq("@{MARKS[i]}_diff")),
		top_annotation = HeatmapAnnotation(lines1 = anno_enriched(gp = gpar(pos_col = "#df8640", neg_col = "#3794bf", lty = 1:n_row_cluster))),
		use_raster = TRUE, raster_quality = 2)
	gap = unit.c(gap, unit(1, "cm"))
	n_heatmap = n_heatmap + 1
}
ht_list2 = ht_list

lines_lgd = Legend(at = c("cluster1", "cluster2"), title = "Lines", legend_gp = gpar(lty = 1:n_row_cluster), type = "lines")

# following chunk is necessary because Legend() needs to open a new graphic device
for(i in seq_along(dev.list())) {
	dev.off()
}

if(on == "tss") {
	pdf(qq("@{OUTPUT_DIR}/plots/cr_enrichedheatmap_on_@{on}_by_gene_@{type}_fdr_@{cutoff}_methdiff_@{meandiff}.pdf"), width = n_heatmap + 4, height = 10)
} else {
	pdf(qq("@{OUTPUT_DIR}/plots/cr_enrichedheatmap_on_@{on}_km_@{K}.pdf"), width = n_heatmap + 4, height = 10)
}
# qqcat("@{type}CR, @{nrow(mat)} rows\n")
# foo = draw(ht_list, gap = gap, annotation_legend_list = list(lines_lgd),
# 	main_heatmap = qq("@{type}CR"), column_title = qq("default, @{nrow(mat)} rows"), km = 2, row_sub_title_side = "left",
# 	heatmap_legend_side = "bottom")
# add_boxplot_of_gene_length(foo)


ht_list = Heatmap(expr_split, show_row_names = FALSE, name = "expr_split", col = c("high" = "red", "low" = "darkgreen"), width = unit(5, "mm")) + ht_list1
foo = draw(ht_list,  annotation_legend_list = list(lines_lgd),
		cluster_rows = FALSE, row_order = row_order, show_row_dend = FALSE,
		column_title = qq("cluster by methylation, @{nrow(mat)} rows"), split = meth_split, row_sub_title_side = "left",
		show_heatmap_legend = FALSE, annotation_legend_side = "right")
add_boxplot_of_gene_length(foo)
i = 0
for(f in names(ht_list1@ht_list)) {
	if(grepl("expr|annotation|CGI|km|CR", f)) next
	decorate_column_title(f, {
		grid.rect(height = unit(0.8, "npc"), gp = gpar(fill = brewer.pal(8, "Set2")[as.integer(i/3)+1], col = NA))
		grid.text(ht_list1@ht_list[[f]]@column_title, gp = gpar(fontsize = 14))
	})
	i = i + 1
}

ht_list = Heatmap(expr_split, show_row_names = FALSE, name = "expr_split", col = c("high" = "red", "low" = "darkgreen"), width = unit(5, "mm")) + ht_list2
foo = draw(ht_list, annotation_legend_list = list(lines_lgd),
		cluster_rows = FALSE, row_order = row_order, show_row_dend = FALSE,
		column_title = qq("cluster by methylation, @{nrow(mat)} rows"), split = meth_split, row_sub_title_side = "left",
		show_heatmap_legend = FALSE)
for(f in names(ht_list2@ht_list)) {
	decorate_column_title(f, {
		grid.rect(height = unit(0.8, "npc"), gp = gpar(fill = brewer.pal(8, "Set2")[as.integer(i/3)+1], col = NA))
		grid.text(ht_list2@ht_list[[f]]@column_title, gp = gpar(fontsize = 14))
	})
	i = i + 1
}

# qqcat("cluster by expression, @{nrow(mat)} rows\n")
# foo = draw(ht_list, gap = gap, annotation_legend_list = list(lines_lgd),
# 	main_heatmap = "expr", cluster_rows = TRUE, show_row_dend = FALSE,
# 	column_title = qq("cluster by expression, @{nrow(mat)} rows"), split = expr_split, row_sub_title_side = "left",
# 	heatmap_legend_side = "bottom")
# add_boxplot_of_gene_length(foo)


# if(on == "tss") {
# 	qqcat("cluster by @{type}CR, @{nrow(mat)} rows\n")
# 	foo = draw(ht_list, gap = gap, annotation_legend_list = list(lines_lgd),
# 		main_heatmap = qq("@{type}CR"), cluster_rows = TRUE, show_row_dend = FALSE,
# 		column_title = qq("cluster by @{type}CR, @{nrow(mat)} rows"), km = 2, row_sub_title_side = "left",
# 		heatmap_legend_side = "bottom")
# 	add_boxplot_of_gene_length(foo)
# }

dev.off()



# for(cutoff in c(0.1, 0.05, 0.01)) {
#     for(meandiff in c(0, 0.1, 0.2, 0.3)) { 
# 		for(on in c("tss")) {
# 		        for(type in c("pos", "neg")) {
# 		            cmd = qq("Rscript-3.1.2 /icgc/dkfzlsdf/analysis/B080/guz/roadmap_analysis/re_analysis/scripts/04.correlated_regions_enrichedheatmap_at_gene.R --on @{on} --rerun --type @{type} --cutoff @{cutoff} --meandiff @{meandiff}")
# 		            cmd = qq("perl /home/guz/project/development/ngspipeline2/qsub_single_line.pl '-l walltime=20:00:00,mem=10G -N cr_enrichedheatmap_@{on}_@{type}_fdr_@{cutoff}_methdiff_@{meandiff}' '@{cmd}'")
# 		            system(cmd)
# 		        }
# 		}
# 	}
# }

# for(k in 1:4) {
#     cmd = qq("Rscript-3.1.2 /icgc/dkfzlsdf/analysis/B080/guz/roadmap_analysis/re_analysis/scripts/04.correlated_regions_enrichedheatmap_at_gene.R --no-rerun --on body --K @{k}")      
#     cmd = qq("perl /home/guz/project/development/ngspipeline2/qsub_single_line.pl '-l walltime=40:00:00,mem=20G -N cr_enrichedheatmap_body_km_@{k}' '@{cmd}'")
#     system(cmd)
# }

