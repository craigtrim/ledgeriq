FROM lambda-base:3.11-arm64
COPY lambda_function.py ${LAMBDA_TASK_ROOT}
COPY prompt.txt ${LAMBDA_TASK_ROOT}
CMD [ "lambda_function.handler" ]
