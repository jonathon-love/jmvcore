
#' @rdname Analysis
#' @export
Image <- R6::R6Class("Image",
    inherit=ResultsElement,
    private=list(
        .path=NA,
        .width=400,
        .height=300,
        .renderInitFun=NA,
        .renderFun=NA,
        .requiresData=FALSE),
    active=list(
        width=function() private$.width,
        height=function() private$.height,
        path=function() private$.path,
        requiresData=function() private$.requiresData),
    public=list(
        initialize=function(
            options,
            width=400,
            height=300,
            renderFun=NULL,
            renderInitFun=NULL,
            requiresData=FALSE,
            name=NULL,
            title='',
            visible=TRUE,
            clearWith='*') {

            super$initialize(
                options=options,
                name=name,
                title=title,
                visible=visible,
                clearWith=clearWith)

            private$.width <- width
            private$.height <- height
            private$.renderFun <- renderFun
            private$.renderInitFun <- renderInitFun
            private$.requiresData <- requiresData

            private$.path <- NULL
        },
        setSize=function(width, height) {
            private$.width  <- width
            private$.height <- height
        },
        isFilled=function() {
            if (private$.stale)
                return(FALSE)
            if (is.null(private$.path))
                return(FALSE)
            return(TRUE)
        },
        print=function() {
            self$.render()
        },
        saveAs=function(path, ...) {

            if ( ! is.character(private$.renderFun))
                stop('no render function', call.=FALSE)

            if (endsWith(tolower(path), '.pdf')) {
                cairo_pdf(
                    file=path,
                    width=private$.width/72,
                    height=private$.height/72)
            } else if (endsWith(tolower(path), '.svg')) {
                svg(
                    file=path,
                    width=private$.width/72,
                    height=private$.height/72)
            } else if (endsWith(tolower(path), '.eps')) {
                cairo_ps(
                    file=path,
                    width=private$.width/72,
                    height=private$.height/72)
            } else if (endsWith(tolower(path), '.png')) {

                multip <- 144 / 72
                grType <- 'cairo'
                if (Sys.info()['sysname'] == 'Windows')
                    grType <- 'windows'

                grDevices::png(type=grType,
                               filename=path,
                               width=private$.width * multip,
                               height=private$.height * multip,
                               bg='transparent',
                               res=72 * multip)
            } else {
                reject('unrecognised format')
            }

            on.exit(grDevices::dev.off())

            self$analysis$.render(funName=private$.renderFun, image=self, ...)
        },
        .render=function(...) {
            if ( ! is.character(private$.renderFun))
                return(FALSE)

            self$analysis$.render(funName=private$.renderFun, image=self, ...)
        },
        .createImages=function(...) {
            if ( ! is.character(private$.renderFun))
                return(FALSE)

            self$analysis$.createImage(funName=private$.renderFun, image=self, ...)
        },
        .setPath=function(path) {
            private$.path <- path
        },
        asString=function() {
            return('')
        },
        asProtoBuf=function(incAsText=FALSE, status=NULL) {

            path <- private$.path
            if (is.null(path))
                path=''

            image <- RProtoBuf_new(jamovi.coms.ResultsImage,
                width=private$.width,
                height=private$.height,
                path=path)

            result <- super$asProtoBuf(incAsText=incAsText, status=status)

            if (self$isFilled()) {

                result$status <- jamovi.coms.AnalysisStatus$ANALYSIS_COMPLETE

            } else if (status == jamovi.coms.AnalysisStatus$ANALYSIS_COMPLETE &&
                ( ! is.null(self$state)) &&
                path == '') {
                    result$status <- jamovi.coms.AnalysisStatus$ANALYSIS_RENDERING
            }

            result$image <- image
            result
        },
        fromProtoBuf=function(element, oChanges, vChanges) {
            if ( ! base::inherits(element, "Message"))
                reject("Image$fromProtoBuf() expects a jamovi.coms.ResultsElement")

            someChanges <- length(oChanges) > 0 || length(vChanges) > 0
            if (someChanges && base::identical('*', private$.clearWith))
                return()

            if (base::any(oChanges %in% private$.clearWith))
                return()

            for (clearName in private$.clearWith) {
                if (base::any(vChanges %in% private$.options$option(clearName)$vars))
                    return()
            }

            super$fromProtoBuf(element, oChanges, vChanges)

            image <- element$image

            private$.width <- image$width
            private$.height <- image$height
            if (image$path == '' || 'theme' %in% oChanges || 'palette' %in% oChanges)
                private$.path <- NULL
            else
                private$.path <- image$path
        })
)

#' @export
#' @importFrom utils .DollarNames
.DollarNames.Image <- function(x, pattern = "") {
    names <- ls(x, all.names=F, pattern = pattern)
    retain <- c('saveAs')
    names <- intersect(names, retain)
    names
}
