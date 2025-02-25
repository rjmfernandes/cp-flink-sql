CREATE TABLE flinkInput (
  `raw` STRING,
  `ts` TIMESTAMP(3) METADATA FROM 'timestamp'
) WITH (
  'connector' = 'kafka',
  'topic' = 'flink-input',
  'properties.bootstrap.servers' = 'kafka.confluent.svc.cluster.local:9092',
  'properties.group.id' = 'testGroup',
  'scan.startup.mode' = 'earliest-offset',
  'format' = 'raw'
);

CREATE TABLE msgCount (
  `count` BIGINT NOT NULL
) WITH (
  'connector' = 'kafka',
  'topic' = 'message-count',
  'properties.bootstrap.servers' = 'kafka.confluent.svc.cluster.local:9092',
  'properties.group.id' = 'testGroup',
  'scan.startup.mode' = 'earliest-offset',
  'format' = 'debezium-json'
);

INSERT INTO msgCount VALUES (1);
