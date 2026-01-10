FROM lambda-base:3.11-arm64
WORKDIR ${LAMBDA_TASK_ROOT}
RUN python -m pip install -U pip
RUN python -m pip install oureliza
COPY lambda_function.py ${LAMBDA_TASK_ROOT}/
CMD [ "lambda_function.handler" ]
