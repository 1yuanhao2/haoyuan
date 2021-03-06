require(synapseClient)
require(rGithubClient)
require(ggplot2)

## SOURCE IN BACKGROUND FUNCTIONS FROM JG
crcRepo <- getRepo("Sage-Bionetworks/crcsc")
sourceRepoFile(crcRepo, "groups/G/pipeline/JGLibrary.R")
code1 <- getPermlink(crcRepo, "groups/G/pipeline/JGLibrary.R")
sourceRepoFile(crcRepo, "groups/G/pipeline/subtypePipelineFuncs.R")
code2 <- getPermlink(crcRepo, "groups/G/pipeline/subtypePipelineFuncs.R")

## SOURCE CODE TO READ IN DATA
sourceRepoFile(crcRepo, "evals/getDataFuncs.R")
code3 <- getPermlink(crcRepo, "evals/getDataFuncs.R")

## THIS SCRIPT
thisCode <- getPermlink(crcRepo, "evals/summarizeGenesets.R")
resFold <- synGet("syn2322802")

## QUERY FOR OUR RESULTS
resQ <- synapseQuery("SELECT id, name, group, dataset, method, stat, evalDate FROM file WHERE parentId=='syn2322802'")
gsQ <- resQ[ resQ$file.method != "eBayes", ]
gsQ$file.evalDate <- as.Date(gsQ$file.evalDate)
gsQ <- gsQ[ which(gsQ$file.evalDate > as.Date("2014-03-18")), ]
## REMOVE ORIGINAL TCGA AND CELL LINE DATASETS
gsQ <- gsQ[ -which(gsQ$file.dataset %in% c("tcga_rnaseq", "sanger", "gsk", "ccle")), ]

dss <- unique(gsQ$file.dataset)
gps <- unique(gsQ$file.group)


## PULL IN ALL OF THE RESULT MATRICES FROM THE GENESET ANALYSES
allDat <- lapply(as.list(gsQ$file.id), function(x){
  a <- synGet(x)
  read.delim(getFileLocation(a), as.is=T, header=T, row.names=1)
})


## INDICATOR MATRICES TO SHOW SIGNIFICANCE AT DIFFERENT LEVELS
allDatInd05 <- lapply(allDat, function(x){
  x <= 0.05
})
allDatInd001 <- lapply(allDat, function(x){
  x <= 0.001
})

## SUBSET OF MATRICES FOR COMPETITIVE MODELS ONLY
compInd <- which(gsQ$file.method %in% c("gsa", "ks"))
theseComp <- gsQ[ compInd, ]
compDat <- allDat[ compInd ]
compDatInd05 <- allDatInd05[ compInd ]
compDatInd001 <- allDatInd001[ compInd ]
gsaInd <- which(gsQ$file.method == "gsa")
theseGsa <- gsQ[ gsaInd, ]
gsaDat <- allDat[ gsaInd ]
## THRESHOLD GSA RESULTS TO LOWER LIMIT OF DETECTION
gsaDat <- lapply(gsaDat, function(x){
  apply(x, c(1,2), function(y){ max(y, 0.0001) })
})

## COLLAPSE TO SEE IF EITHER COMPETITIVE MODEL SHOWS SIGNIFICANCE
## FOR EACH GROUP AND DATASET
compRes05 <- list()
compRes001 <- list()
for(gp in gps){
  compRes05[[gp]] <- list()
  compRes001[[gp]] <- list()
  for( ds in dss ){
    idx <- which( theseComp$file.dataset==ds & theseComp$file.group==gp )
    if( length(idx) == 1 ){
      compRes05[[gp]][[ds]] <- compDatInd05[ idx ]
      compRes001[[gp]][[ds]] <- compDatInd001[ idx ]
    } else if( length(idx) == 2 ){
      compRes05[[gp]][[ds]] <- do.call("|", compDatInd05[ idx ])
      compRes001[[gp]][[ds]] <- do.call("|", compDatInd001[ idx ])
    }
  }
}

## FOR EACH GROUP, COLLAPSE AND COUNT THE NUMBER OF SIGNIFICANT DATASETS
compResGp05 <- lapply(compRes05, function(x){
  Reduce("+", x)
})
compResGp001 <- lapply(compRes001, function(x){
  Reduce("+", x)
})



## PLOTS PER GROUP
## FOR SIGNIFICANCE AT 0.05
for(i in names(compResGp05) ){
  x <- compResGp05[[i]]
  plotDF <- data.frame(geneset = rep(rownames(x), ncol(x)),
                       subtype = rep(colnames(x), each=nrow(x)),
                       count = as.numeric(x))
  p <- ggplot(data=plotDF, aes(x=subtype, y=count, fill=subtype)) +
    geom_bar(stat="identity") + xlab("") + ylab("number of signficant datasets (0.05)") + ggtitle(i) +
    facet_wrap(facets=(~ geneset), ncol=3)
  
  plotPath <- file.path(tempdir(), paste("genesetsAcrossDatasets-", i, "-p05.png", sep=""))
  png(plotPath, width=900, height=600)
  show(p)
  dev.off()
  synPlot <- synStore(File(path=plotPath, parentId="syn2420832"),
                      activity=Activity(name="geneset plots",
                                        used=list(
                                          list(url=thisCode, name=basename(thisCode), wasExecuted=T),
                                          list(entity=resFold, wasExecuted=F))))
}
## FOR SIGNIFICANCE AT 0.001
for(i in names(compResGp001) ){
  x <- compResGp001[[i]]
  plotDF <- data.frame(geneset = rep(rownames(x), ncol(x)),
                       subtype = rep(colnames(x), each=nrow(x)),
                       count = as.numeric(x))
  p <- ggplot(data=plotDF, aes(x=subtype, y=count, fill=subtype)) +
    geom_bar(stat="identity") + xlab("") + ylab("number of signficant datasets (0.001)") + ggtitle(i) +
    facet_wrap(facets=(~ geneset), ncol=3)
  
  plotPath <- file.path(tempdir(), paste("genesetsAcrossDatasets-", i, "-p001.png", sep=""))
  png(plotPath, width=900, height=600)
  show(p)
  dev.off()
  synPlot <- synStore(File(path=plotPath, parentId="syn2420832"),
                      activity=Activity(name="geneset plots",
                                        used=list(
                                          list(url=thisCode, name=basename(thisCode), wasExecuted=T),
                                          list(entity=resFold, wasExecuted=F))))
}


## PLOTS PER GROUP
## FISHER META ANALYSIS P-VALUE
# 1 - pchisq(-2 * sum(log(pvals)),2 * length(pvals))
for(gp in gps){
  idx <- which( theseGsa$file.group == gp )
  
  chsq <- -2*Reduce("+", lapply(gsaDat[ idx ], log))
  pval <- apply(chsq, c(1,2), function(x){
    1-pchisq(x, 2*length(idx))
  })
  x <- -1*log10(pval)
  x <- apply(x, c(1,2), function(y){
    min(y, 20)
  })
  
  plotDF <- data.frame(geneset = rep(rownames(x), ncol(x)),
                       subtype = rep(colnames(x), each=nrow(x)),
                       count = as.numeric(x))
  p <- ggplot(data=plotDF, aes(x=subtype, y=count, fill=subtype)) +
    geom_bar(stat="identity") + xlab("") + ylab("-log10(fisher meta analysis pval)") + ggtitle(gp) +
    facet_wrap(facets=(~ geneset), ncol=3)
  
  plotPath <- file.path(tempdir(), paste("genesetsMetaAnalysis-", gp, ".png", sep=""))
  png(plotPath, width=900, height=600)
  show(p)
  dev.off()
  synPlot <- synStore(File(path=plotPath, parentId="syn2420832"),
                      activity=Activity(name="geneset plots",
                                        used=list(
                                          list(url=thisCode, name=basename(thisCode), wasExecuted=T),
                                          list(entity=resFold, wasExecuted=F))))
}


## PLOTS BY DATASET AND GENESET
for(ds in dss){
  idx <- gsQ$file.dataset == ds
  these <- gsQ[ idx, ]
  
  thisDat <- allDat[ idx ]
  minPvals <- lapply(thisDat, function(x){
    m <- apply(x, 1, min)
    m[m==0] <- 0.001
    m
  })
  mpMat <- do.call(cbind, minPvals)
  
  for( gs in rownames(mpMat) ){
    plotDF <- these
    plotDF$genesetPval <- -1*log10(as.numeric(mpMat[gs, ]))
    plotDF$method <- plotDF$file.method
    plotDF$method <- sub("globaltest", " global", plotDF$method)
    plotDF$method <- sub("tukey", " tukey", plotDF$method)
    p <- qplot(method, data=plotDF, geom="bar", weight=genesetPval, facets=(. ~ file.group), fill=method, 
               main=paste("dataset: ", ds, "  ||  geneset: ", gs, sep=""), ylab="-log10(pval)", xlab="") +
      geom_hline(yintercept=c(-1*log10(0.05), -1*log10(0.001)), linetype=2)
    
    plotPath <- file.path(tempdir(), paste("datasetByGeneset-", ds, "-", gs, ".png", sep=""))
    png(plotPath, width=900, height=600)
    show(p)
    dev.off()
    synPlot <- synStore(File(path=plotPath, parentId="syn2420834"),
                        activity=Activity(name="geneset plots",
                                          used=list(
                                            list(url=thisCode, name=basename(thisCode), wasExecuted=T),
                                            list(entity=resFold, wasExecuted=F))))
  }
}

