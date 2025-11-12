FROM lambda-base:3.11-arm64

# Copy Lambda function and prompt template
COPY lambda_function.py ${LAMBDA_TASK_ROOT}
COPY prompt.txt ${LAMBDA_TASK_ROOT}

# Set the CMD to your handler
CMD [ "lambda_function.handler" ]
