# Dockerfile for running your AWS Lambda code locally via the RIE
FROM public.ecr.aws/lambda/python:3.12

# Copy the exact ZIP you deploy to AWS
COPY dashboard-app/backend/dashboard-backend.zip /var/task/package.zip

# Unzip in-place and delete the archive
RUN python3 - << 'EOF'
import zipfile
zipfile.ZipFile('/var/task/package.zip').extractall('/var/task')
EOF
RUN rm /var/task/package.zip

# When you run: docker run ... local-lambda
# you must pass the handler name as the first argument (see README),
# but by default we'll point it at your Mangum handler:
CMD ["main.handler"]
