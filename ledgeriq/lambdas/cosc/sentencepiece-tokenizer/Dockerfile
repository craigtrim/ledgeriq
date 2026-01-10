FROM lambda-base:3.11-arm64
WORKDIR ${LAMBDA_TASK_ROOT}
RUN python -m pip install -U pip
RUN python -m pip install --only-binary=:all: sentencepiece
COPY lambda_function.py tokenizer.model ${LAMBDA_TASK_ROOT}/
CMD [ "lambda_function.handler" ]
