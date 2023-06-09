#!/bin/bash
# Licensed to the Apache Software Foundation (ASF) under one
#  or more contributor license agreements.  See the NOTICE file
#  distributed with this work for additional information
#  regarding copyright ownership.  The ASF licenses this file
#  to you under the Apache License, Version 2.0 (the
#  "License"); you may not use this file except in compliance
#  with the License.  You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

#########################
# The command line help #
#########################
usage() {
  echo "Usage: $0"
  echo "   -n |--num-kafka-records, (required) number of kafka records to generate in a batch"
  echo "   -b |--num-batch, (optional) number of batches of records to generate (default is 1)"
  echo "   -f |--raw-file, (optional) raw file for the kafka records"
  echo "   -k |--kafka-topic, (optional) Topic name for Kafka"
  echo "   -m |--num-kafka-partitions, (optional) number of kafka partitions"
  echo "   -r |--record-key, (optional) field to use as record key"
  echo "   -o |--record-key-offset, (optional) record key offset to start with (default is 0)"
  echo "   -l |--num-hudi-partitions, (optional) number of hudi partitions"
  echo "   -p |--partition-key, (optional) field to use as partition"
  exit 1
}

case "$1" in
--help)
  usage
  exit 0
  ;;
esac

if [ $# -lt 1 ]; then
  echo "Illegal number of parameters"
  usage
  exit 0
fi


## defaults
rawDataFile=./bin/demo/data/batch_1.json
kafkaBrokerHostname=localhost
kafkaTopicName=stock-ticks
numKafkaPartitions=4
recordKey=volume
numHudiPartitions=5
partitionField=date
numBatch=1
recordValue=0

while getopts ":n:b:tf:k:m:r:o:l:p:s:-:" opt; do
  case $opt in
  n)
    numRecords="$OPTARG"
    printf "Argument num-kafka-records is %s\n" "$numRecords"
    ;;
  b)
    numBatch="$OPTARG"
    printf "Argument num-batch is %s\n" "$numBatch"
    ;;
  t)
    recreateTopic="N"
    printf "Argument recreate-topic is N (reuse Kafka topic) \n"
    ;;
  f)
    rawDataFile="$OPTARG"
    printf "Argument raw-file is %s\n" "$rawDataFile"
    ;;
  k)
    kafkaTopicName="$OPTARG"
    printf "Argument kafka-topic is %s\n" "$kafkaTopicName"
    ;;
  m)
    numKafkaPartitions="$OPTARG"
    printf "Argument num-kafka-partitions is %s\n" "$numKafkaPartitions"
    ;;
  r)
    recordKey="$OPTARG"
    printf "Argument record-key is %s\n" "$recordKey"
    ;;
  o)
    recordValue="$OPTARG"
    printf "Argument record-key-offset is %s\n" "$recordValue"
    ;;
  l)
    numHudiPartitions="$OPTARG"
    printf "Argument num-hudi-partitions is %s\n" "$numHudiPartitions"
    ;;
  p)
    partitionField="$OPTARG"
    printf "Argument partition-key is %s\n" "$partitionField"
    ;;
  -)
    echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

# Generate kafka messages from raw records
# Each records with unique keys and generate equal messages across each hudi partition
partitions={}
for ((i = 0; i < ${numHudiPartitions}; i++)); do
  partitions[$i]="partition_"$i
done

events_file=/tmp/kcat-input.events
rm -f ${events_file}

totalNumRecords=$((numRecords + recordValue))

for ((i = 1;i<=numBatch;i++)); do
  rm -f ${events_file}
  date
  echo "Start batch $i ..."
  batchRecordSeq=0
  for (( ; ; )); do
    while IFS= read line; do
      for partitionValue in "${partitions[@]}"; do
        echo $line | jq --arg recordKey $recordKey --arg recordValue $recordValue --arg partitionField $partitionField --arg partitionValue $partitionValue -c '.[$recordKey] = $recordValue | .[$partitionField] = $partitionValue' >>${events_file}
        ((recordValue = recordValue + 1))
        ((batchRecordSeq = batchRecordSeq + 1))

        if [ $batchRecordSeq -eq $numRecords ]; then
          break
        fi
      done

      if [ $batchRecordSeq -eq $numRecords ]; then
        break
      fi
    done <"$rawDataFile"

    if [ $batchRecordSeq -eq $numRecords ]; then
        date
        echo " Record key until $recordValue"
        sleep 20
        break
      fi
  done

  echo "publish to Redpanda ..."
  grep -v '^$' ${events_file} | kcat -P -b ${kafkaBrokerHostname}:9092 -t ${kafkaTopicName}
done
