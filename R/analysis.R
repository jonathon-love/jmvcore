
Analysis <- R6::R6Class("Analysis",
    private=list(
        .datasetId="",
        .analysisId="",
        .name="",
        .package="",
        .title="",
        .options=NA,
        .results=NA,
        .status="none",
        .init=function() NULL,
        .run=function() NULL,
        .readDataset=NA,
        .readDatasetHeader=NA,
        .statePathSource=NA,
        .resourcesPathSource=NA,
        .checkpointCB=NA,
        .data=NA,
        .header=NA,
        .info=NA,
        .changed=character(),
        .checkpoint=function(flush=TRUE) {
            if (is.null(private$.checkpointCB))
                return()
            if (flush)
                private$.checkpointCB(RProtoBuf::serialize(self$asProtoBuf(), NULL))
            else
                private$.checkpointCB(NULL)
        },
        .sourcifyOption=function(option) {
            if ( ! ((is.numeric(value) && isTRUE(all.equal(value, option$default))) || base::identical(value, option$default))) {
                return(paste0(option$name, '=', sourcify(value, '    ')))
            }
            ''
        },
        .asArgs=function() {
            source <- ''
            sep <- '\n    '

            for (option in private$.options$options) {

                if (option$name == 'data')
                    next()

                as <- private$.sourcifyOption(option)
                if ( ! base::identical(as, '')) {
                    source <- paste0(source, sep, as)
                    sep <- paste0(',\n    ')
                }
            }

            source
        }),
    active=list(
        analysisId=function() private$.analysisId,
        name=function() private$.name,
        data=function() private$.data,
        options=function() private$.options,
        results=function() private$.results,
        status=function() private$.status),
    public=list(
        initialize=function(package, name, options, data=NULL, datasetId="", analysisId="") {

            private$.package <- package
            private$.name    <- name
            private$.options <- options
            private$.data <- data

            private$.analysisId <- analysisId
            private$.datasetId  <- datasetId

            private$.results <- jmvcore::Group$new(options=options)
            private$.results$.parent <- self
            private$.options$analysis <- self

            resultsDef <- loadResultsInfo(package, name)
            if ( ! is.null(resultsDef))
                private$.results$.setup(resultsDef)

            private$.options$addChangeListener(private$.optionsChangedHandler)

            private$.checkpointCB <- NULL
        },
        check=function() {
            private$.options$check()
        },
        init=function() {
            if (private$.status != "none")
                return()

            wasNull <- FALSE

            if (is.null(private$.data)) {
                private$.data <- self$readDataset(TRUE)
                wasNull <- TRUE
            } else {
                private$.data <- select(private$.data, self$options$varsRequired)
            }

            self$options$check()
            self$results$.update()

            result <- try({
                private$.init()
            })

            if (wasNull)
                private$.data <- NULL

            if (base::inherits(result, 'try-error')) {
                errorMessage <- extractErrorMessage(result)
                private$.results$setError(errorMessage)
                private$.status <- 'error'
            } else {
                private$.status <- 'inited'
            }
        },
        run=function(silent=FALSE) {

            if (private$.status != "inited")
                self$init()

            wasNull <- FALSE

            if (is.null(private$.data)) {
                wasNull <- TRUE
                private$.data <- self$readDataset()
            }

            private$.status <- "running"

            if (silent) {
                result <- try({
                    private$.run()
                })
            } else {
                result <- private$.run()
            }

            if (wasNull)
                private$.data <- NULL

            if (base::inherits(result, 'try-error')) {
                errorMessage <- extractErrorMessage(result)
                private$.results$setError(errorMessage)
                private$.status <- 'error'
            } else {
                private$.status <- 'complete'
            }
        },
        print=function() {
            cat(self$results$asString())
        },
        render=function(...) {
            private$.results$.render(...)
        },
        .save=function() {
            path <- private$.statePathSource()
            pb <- self$asProtoBuf(incOptions=TRUE)
            RProtoBuf::serialize(pb, path)
        },
        .load=function(vChanges=character()) {

            initProtoBuf()

            path <- private$.statePathSource()

            if (base::file.exists(path)) {
                pb <- RProtoBuf::read(jmvcoms.AnalysisResponse, path)

                options <- rjson::fromJSON(pb$options)
                oChanges <- list()

                for (name in names(options)) {
                    old <- options[[name]]
                    now <- private$.options$get(name)
                    if ( ! base::identical(old, now))
                        oChanges[[length(oChanges)+1]] <- name
                }

                private$.results$fromProtoBuf(pb$results, oChanges, vChanges)
            }
        },
        .render=function(funName, image, ppi=72, ...) {

            if ( ! is.null(image$path))
                return()

            render <- private[[funName]]

            if (image$visible == FALSE)
                return()

            if (is.function(render) == FALSE) {
                image$.setPath(NULL)
                return()
            }

            if (is.function(private$.resourcesPathSource)) {

                name <- base64enc::base64encode(base::charToRaw(image$name))
                paths <- private$.resourcesPathSource(name, "png")

                base::Encoding(paths$rootPath) <- 'UTF-8'
                base::Encoding(paths$relPath)  <- 'UTF-8'

                fullPath <- paste0(paths$rootPath, '/', paths$relPath)

                multip <- ppi / 72

                grType <- 'cairo'
                if (Sys.info()['sysname'] == 'Windows')
                    grType <- 'windows'

                grDevices::png(type=grType,
                    filename=fullPath,
                    width=image$width * multip,
                    height=image$height * multip,
                    bg='transparent',
                    res=72 * multip)
            }

            wasNull <- FALSE

            if (image$requiresData && is.null(private$.data)) {
                wasNull <- TRUE
                private$.data <- self$readDataset()
            }

            rendered <- render(image)

            if (wasNull)
                private$.data <- NULL

            if (is.function(private$.resourcesPathSource)) {

                grDevices::dev.off()

                if (rendered)
                    image$.setPath(paths$relPath)
                else
                    image$.setPath(NULL)

            } else {

                image$.setPath(NULL)
            }
        },
        .setReadDatasetSource=function(read) {
            private$.readDataset <- read
        },
        .setReadDatasetHeaderSource=function(read) {
            private$.readDatasetHeader <- read
        },
        .setStatePathSource=function(statePath) {
            private$.statePathSource <- statePath
        },
        .setResourcesPathSource=function(resourcesPathSource) {
            private$.resourcesPathSource <- resourcesPathSource
        },
        .setCheckpoint=function(checkpoint) {
            private$.checkpointCB <- checkpoint
        },
        .readState=function() {
            try({
                if (is.function(private$.statePathSource)) {
                    statePath <- private$.statePathSource()
                    if (base::file.exists(statePath)) {
                        conn <- file(statePath, open="rb", raw=TRUE)
                        pb <- RProtoBuf::read(jmvcoms.ResultsElement, conn)
                        base::close(conn)

                        self$results$fromProtoBuf(pb)
                    }
                }
            })
        },
        .saveState=function() {

            if (is.function(private$.statePathSource)) {
                statePath <- private$.statePathSource()
                conn <- file(statePath, open="wb", raw=TRUE)
                RProtoBuf::serialize(self$results$asProtoBuf(), conn)
                base::close(conn)
            }
        },
        readDataset=function(headerOnly=FALSE) {

            if (headerOnly)
                dataset <- private$.readDatasetHeader(self$options$varsRequired)
            else
                dataset <- private$.readDataset(self$options$varsRequired)

            dataset
        },
        optionsChangedHandler=function(optionNames) {
            private$.status <- "none"
        },
        asProtoBuf=function(incOptions=FALSE, incAsText=FALSE) {

            self$init()
            initProtoBuf()

            response <- RProtoBuf::new(jmvcoms.AnalysisResponse)
            response$datasetId  <- private$.datasetId
            response$analysisId <- self$analysisId

            if (incAsText) {
                response$incAsText <- TRUE
                syntax <- RProtoBuf::new(jmvcoms.ResultsElement, name='syntax', syntax=self$asSource())
                response$results <- self$results$asProtoBuf(incAsText=incAsText, prepend=syntax);
            } else {
                response$results <- self$results$asProtoBuf(incAsText=incAsText);
            }

            if (incOptions)
                response$options <- private$.options$asJSON()

            if (private$.status == "inited") {
                response$status <- jmvcoms.AnalysisStatus$ANALYSIS_INITED;
            } else if (private$.status == "running") {
                response$status <- jmvcoms.AnalysisStatus$ANALYSIS_RUNNING;
            } else if (private$.status == "complete") {
                response$status <- jmvcoms.AnalysisStatus$ANALYSIS_COMPLETE;
            } else {
                error <- RProtoBuf::new(jmvcoms.Error)
                error$message <- private$.error
                response$error <- error
                response$status <- jmvcoms.AnalysisStatus$ANALYSIS_ERROR;
            }

            response
        },
        asSource=function() {
            paste0(private$.package, '::', private$.name, '(\n    data=data, ', private$.asArgs(), ')')
        })
)