

CREATE TABLE msgCount (
  `count` BIGINT NOT NULL
) WITH (
  'connector' = 'kafka',
  'topic' = 'message-count',
  'properties.bootstrap.servers' = 'kafka.confluent.svc.cluster.local:9092',
  'properties.group.id' = 'testBatchGroup',
  'scan.startup.mode' = 'earliest-offset',
  'format' = 'debezium-json'
);

INSERT INTO msgCount VALUES (1);
