ReadDescfile <- function(filename) {
  descfile <- read.dcf(filename)
  values <- as.vector(descfile[1, ])
  encoding <- "utf8"
  if (inherits(filename, "character")){
    encoding <- GuessEncoding(filename)
  }
  if ("Encoding" %in% colnames(descfile)) {
    encoding <- descfile[colnames(descfile) == "Encoding"]
  }
  if (!tolower(encoding) %in% c("utf8", "utf-8", "cannot")) {
    values <- iconv(as.vector(descfile[1, ]), encoding, "utf8")
  }
  as.data.table(list(key=colnames(descfile), value=values))
}

ReadCRANDescfile <- function(package, version, datadir) {
  loginfo("Parsing CRAN DESCRIPTION file from %s %s",
          package, version, logger="description.cran")
  path <- file.path(datadir, package, version, package, "DESCRIPTION")
  if (file.exists(path)) ReadDescfile(path)
}

ReadGithubDescfile <- function(repository, ref, datadir) {
  loginfo("Parsing Github DESCRIPTION file from %s %s",
          repository, ref, logger="description.github")
  repo.name <- ParseGithubRepositoryName(repository)
  RunGit(function() {
    filename <- file.path(repo.name$subdir, "DESCRIPTION")
    f <- system2("git", c("ls-tree", ref, filename), stdout=TRUE)
    if (length(f)) {
      args <- c("cat-file", "-p", strsplit(f, " |\t")[[1]][3])
      f <- textConnection(system2("git", args, stdout=TRUE))
      res <- tryCatch(ReadDescfile(f), error=function(e) NULL)
      close(f)
      res
    }
  }, file.path(datadir, repo.name$owner, repo.name$repository))
}

Descfiles <- function(index, datadir) {
  res <- rbindlist(mapply(function(source, repository, ref) {
    dir <- file.path(datadir, source)
    if (source == "cran") {
      res <- ReadCRANDescfile(repository, ref, file.path(dir, "packages"))
    } else if (source == "github") {
      res <- ReadGithubDescfile(repository, ref, file.path(dir, "repos"))
    } else {
      stop(sprintf("Unknown source: %s", source))
    }
    if (!is.null(res) && nrow(res)) {
      cbind(data.table(source, repository, ref), res)
    }
  }, index$source, index$repository, index$ref, SIMPLIFY=FALSE))
  re <- "^\\s*(\\d+([-.]\\d+)*\\S*)(\\s.*)?$"
  if (nrow(res)) res[key == "Version", value := sub(re, "\\1", value)]
}

ExtractDescriptionFiles <- function(datadir, db="rdata", host="mongodb://localhost") {
  index <- as.data.table(mongo("index", db, host)$find())

  con <- mongo("description", db, host)
  message("Reading DESCRIPTION files")
  t <- system.time({
    missing <- MissingEntries(index, con)
    descfiles <- Descfiles(missing, datadir)
  })
  message(sprintf("DESCRIPTION files read in %.3fs", t[3]))
  if (!is.null(descfiles) && nrow(descfiles)) con$insert(descfiles)
}
