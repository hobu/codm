#!/bin/bash

set -e
echo "Hello , this is CODM docker!"

BUCKET="$4"
COLLECT="$5"
OUTPUT="$6"

echo "processing collect '$COLLECT' from bucket $BUCKET to $OUTPUT"

cd /code

mkdir /local/images
ln -s /local/images /code/images

aws s3 cp s3://$BUCKET/settings.yaml .

# try using an overriden settings file
aws s3 cp s3://$BUCKET/$COLLECT/settings.yaml .  || exit 0
aws s3 sync s3://$BUCKET/$COLLECT/ /local/images --no-progress

#python3 /code/run.py --rerun-all --project-path ..
python3 /code/run.py --rerun-all --project-path .. 2>&1 > odm_$COLLECT-process.log

ls -al

# copy ODM products
PRODUCTS=$(ls -d odm_*)
for val in $PRODUCTS;
do
    aws s3 sync $val s3://$BUCKET/$COLLECT/$OUTPUT/$val --no-progress
done

# copy the log
aws s3 cp odm_$COLLECT-process.log s3://$BUCKET/$COLLECT/$OUTPUT/odm_$COLLECT-process.log

# try to copy the EPT data (it isn't named odm_*)
aws s3 sync entwine_pointcloud s3://$BUCKET/$COLLECT/$OUTPUT/entwine_pointcloud --no-progress  || exit 0







