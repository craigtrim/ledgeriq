FROM lambda-base:3.11-arm64

# Copy and install Python dependencies
COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt

# Copy Lambda function and tool configuration
COPY lambda_function.py ${LAMBDA_TASK_ROOT}/
COPY tools.json ${LAMBDA_TASK_ROOT}/

CMD [ "lambda_function.handler" ]
