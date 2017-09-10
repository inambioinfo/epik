\name{cr_concatenate}
\alias{cr_concatenate}
\title{
Concatenate CR objects
}
\description{
Concatenate CR objects
}
\usage{
cr_concatenate(...)
}
\arguments{

  \item{...}{correlated regions}

}
\details{
CRs are generated by chromosome. However some downstream analysis needs CRs from all chromosomes
such as calculating FDR (by \code{\link{cr_add_fdr_column}}) and \code{\link{cr_enriched_heatmap}}. This function just simply
concatenates all CRs and also keeps the CR configurations in the final concatenated object.
}
\value{
A concatenated CR object
}
\author{
Zuguang Gu <z.gu@dkfz.de>
}
\examples{
# There is no example
NULL

}
