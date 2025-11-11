# extract-document-text-api

![Runtime](https://img.shields.io/badge/Runtime-Python%203.11-3776AB?logo=python)
![Type](https://img.shields.io/badge/Type-API-ff69b4)
![Pattern](https://img.shields.io/badge/Pattern-Express-blue)
![Integration](https://img.shields.io/badge/Integration-Step%20Functions-FF9900)

API Gateway wrapper that routes PDF/image documents to appropriate OCR Step Functions. Performs file type detection and invokes Express Step Functions synchronously with 15-minute timeout.
