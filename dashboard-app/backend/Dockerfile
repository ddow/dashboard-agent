# dashboard-app/backend/Dockerfile

FROM public.ecr.aws/lambda/python:3.12

# Default secret key used when none provided
ENV SECRET_KEY=change-me

# Copy the ZIP you build locally into the container
# (make sure this path is correct relative to where you run `docker build`)
# Changed to relative path from context
COPY dashboard-backend.zip /var/task/package.zip

# Unzip it in‐container and remove the ZIP
RUN python3 -c "import zipfile; zipfile.ZipFile('/var/task/package.zip').extractall('/var/task')" \
 && rm /var/task/package.zip

# Tell the RIE which handler to invoke
CMD ["main.handler"]