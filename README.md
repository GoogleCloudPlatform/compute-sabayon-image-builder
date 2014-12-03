## Sabayon Linux Image Builder for GCE

Creates a Sabayon Linux image that can run on Google Compute Engine.

The image is configured close to the recommendations listed on [Building an image from scratch](https://developers.google.com/compute/docs/images#buildingimage).

These scripts are written in Bash.

## Usage

### Install and Configure Cloud SDK (one time setup)
```
# Install Cloud SDK (https://developers.google.com/cloud/sdk/)
# For linux:
curl https://sdk.cloud.google.com | bash

gcloud auth login
gcloud config set project <project>
# Your project ID in Cloud Console, https://console.developers.google.com/
```

### Create the image, locally
```
./build.sh
# Upload to Cloud Storage, you can create a bucket through the Google
# Developers Console, under Storage -> Cloud Storage.
gsutil cp sabayon.tar.gz gs://${BUCKET}/sabayon.tar.gz

# Add image to project
gcloud compute images create sabayon \
  --source-uri gs://${BUCKET}/sabayon.tar.gz \
  --description "Sabayon Linux for Compute Engine"
```


## Contributing changes

* See [CONTRIB.md](CONTRIB.md)


## Licensing
All files in this repository are under the [Apache License, Version 2.0](LICENSE) unless noted otherwise.
