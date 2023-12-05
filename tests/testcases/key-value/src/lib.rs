use anyhow::{ensure, Result};
use itertools::sorted;
use spin_sdk::{
    http_component,
    key_value::{Error, Store},
};

#[http_component]
fn handle_request(req: http::Request<()>) -> Result<http::Response<()>> {
    let query = req
        .uri()
        .query()
        .expect("Should have a testkey query string");
    let query: std::collections::HashMap<String, String> = serde_qs::from_str(query)?;
    let init_key = query
        .get("testkey")
        .expect("Should have a testkey query string");
    let init_val = query
        .get("testval")
        .expect("Should have a testval query string");

    let store = Store::open_default()?;

    let result = store.get(init_key)?;
    ensure!(
        Some(init_val.as_bytes()) == result.as_deref(),
        "Expected to look up {init_key} and get {init_val} but actually got {:?}",
        result.as_deref().map(String::from_utf8_lossy)
    );

    ensure!(
        sorted(vec!["bar".to_owned(), init_key.to_owned()]).collect::<Vec<_>>()
            == sorted(store.get_keys()?).collect::<Vec<_>>(),
        "Expected exectly keys 'bar' and '{}' but got '{:?}'",
        init_key,
        &store.get_keys()?
    );

    store.delete(init_key)?;

    ensure!(&[] as &[String] == &store.get_keys()?);

    Ok(http::Response::builder().status(200).body(())?)
}
