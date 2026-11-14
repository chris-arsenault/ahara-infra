use super::grants;
use testcontainers::{
    core::{IntoContainerPort, WaitFor},
    runners::AsyncRunner,
    GenericImage, ImageExt,
};

#[tokio::test]
async fn named_schemas_keep_writes_and_private_data_out_of_map_reads() {
    let container = GenericImage::new("postgis/postgis", "16-3.5")
        .with_exposed_port(5432.tcp())
        .with_wait_for(WaitFor::message_on_stderr(
            "database system is ready to accept connections",
        ))
        .with_env_var("POSTGRES_HOST_AUTH_METHOD", "trust")
        .start()
        .await
        .unwrap();
    let port = container.get_host_port_ipv4(5432).await.unwrap();
    let (db, connection) = tokio_postgres::connect(
        &format!("host=127.0.0.1 port={port} user=postgres dbname=postgres"),
        tokio_postgres::NoTls,
    )
    .await
    .unwrap();
    tokio::spawn(connection);
    db.batch_execute(
        "CREATE ROLE map_writer; CREATE ROLE map_reader;
         CREATE ROLE generation_writer; CREATE ROLE generation_reader;
         CREATE EXTENSION IF NOT EXISTS postgis;",
    )
    .await
    .unwrap();
    for _ in 0..2 {
        db.batch_execute(&grants("map", "map_writer", "map_reader"))
            .await
            .unwrap();
        db.batch_execute(&grants(
            "generation",
            "generation_writer",
            "generation_reader",
        ))
        .await
        .unwrap();
    }
    db.batch_execute(
        "SET ROLE map_writer;
         CREATE TABLE map.places(id serial PRIMARY KEY, shape geometry);
         INSERT INTO map.places(shape) VALUES(ST_Point(1,2));
         RESET ROLE; SET ROLE generation_writer;
         CREATE TABLE generation.inputs(id serial PRIMARY KEY);
         RESET ROLE; SET ROLE map_reader;",
    )
    .await
    .unwrap();
    assert!(db
        .query("SELECT ST_X(shape) FROM map.places", &[])
        .await
        .is_ok());
    assert!(db.batch_execute("DELETE FROM map.places").await.is_err());
    assert!(db
        .query("SELECT * FROM generation.inputs", &[])
        .await
        .is_err());
    assert!(db
        .batch_execute("CREATE TABLE map.injected(id int)")
        .await
        .is_err());
    db.batch_execute("RESET ROLE; SET ROLE map_writer;")
        .await
        .unwrap();
    assert!(db
        .query("SELECT * FROM generation.inputs", &[])
        .await
        .is_err());
    db.batch_execute("RESET ROLE; SET ROLE generation_writer;")
        .await
        .unwrap();
    assert!(db.query("SELECT * FROM map.places", &[]).await.is_err());
}
