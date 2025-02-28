package test;

import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.table.api.*;
import org.apache.flink.table.api.bridge.java.StreamTableEnvironment;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;

public class FlinkSqlTest {
    @Test
    void testValuesConnector() {
        StreamExecutionEnvironment execEnv = StreamExecutionEnvironment.getExecutionEnvironment();

        TableEnvironment tableEnv = StreamTableEnvironment.create(execEnv);

        // Register 'VALUES' connector
        tableEnv.executeSql(
                "CREATE TABLE test_table (" +
                        "  id INT, " +
                        "  name STRING " +
                        ") WITH ('connector' = 'values')"
        );

        tableEnv.executeSql("INSERT INTO test_table VALUES (1, 'Alice'), (2, 'Bob')");
        Table result = tableEnv.sqlQuery("SELECT COUNT(*) FROM test_table");


        // Verify the table exists
        Assertions.assertEquals("test_table", tableEnv.listTables()[0]);
        //Assertions.assertEquals(2,result.execute().collect().next().getField(0));
    }
}