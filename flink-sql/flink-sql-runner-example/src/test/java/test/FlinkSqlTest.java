package test;

import org.apache.flink.table.api.*;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;

public class FlinkSqlTest {
    @Test
    void testValuesConnector() {
        TableEnvironment tableEnv = TableEnvironment.create(EnvironmentSettings.inBatchMode());

        // Register 'VALUES' connector
        tableEnv.executeSql(
                "CREATE TABLE test_table (" +
                        "  id INT, " +
                        "  name STRING " +
                        ") WITH ('connector' = 'values')"
        );

        // Verify the table exists
        Assertions.assertEquals("test_table", tableEnv.listTables()[0]);
    }
}

