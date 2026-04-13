CREATE TABLE myevent (
  `id` STRING,
  `value` INT NOT NULL,
  `event_time` TIMESTAMP(3),
  `category` STRING,
  WATERMARK FOR `event_time` AS `event_time`
) WITH (
  'connector' = 'kafka',
  'topic' = 'myevent',
  'properties.bootstrap.servers' = 'kafka.confluent.svc.cluster.local:9071',
  'properties.group.id' = 'testGroup',
  'scan.startup.mode' = 'earliest-offset',
  'value.format' = 'avro-confluent',
  'value.avro-confluent.url' = 'http://schemaregistry.confluent.svc.cluster.local:8081'
);

CREATE TABLE myaggregated (
  `window_start` TIMESTAMP(3),
  `category` STRING,
  `total_value` INT NOT NULL,
  `event_count` BIGINT NOT NULL
) WITH (
  'connector' = 'kafka',
  'topic' = 'myaggregated',
  'properties.bootstrap.servers' = 'kafka.confluent.svc.cluster.local:9071',
  'properties.transaction.timeout.ms' = '300000',
  'value.format' = 'avro-confluent',
  'value.avro-confluent.url' = 'http://schemaregistry.confluent.svc.cluster.local:8081',
  'value.avro-confluent.subject' = 'myaggregated-value'
);

INSERT INTO `myaggregated`
SELECT
  window_start,
  category,
  CAST(SUM(`value`) AS INT) AS total_value,
  COUNT(`id`) AS event_count
FROM
  TABLE(
    TUMBLE(
      TABLE `myevent`,
      DESCRIPTOR(`event_time`),
      INTERVAL '10' SECOND
    )
  )
GROUP BY
  window_start,
  window_end,
  category;
