# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
ARG VERSION

# Stock LlamaParse OCR, republished under our registry. No license validator in
# this image (verified: no "llamaindex-byoc" anchor), so nothing to patch.
FROM docker.io/llamaindex/llamacloud-llamaparse-ocr:${VERSION}
