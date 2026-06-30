use aws_sdk_ssm::{types::ParameterType, Client as SsmClient};
use lambda_runtime::Error;

pub async fn read_secure_parameter(
    ssm: &SsmClient,
    name: &str,
    label: &str,
) -> Result<String, Error> {
    ssm.get_parameter()
        .name(name)
        .with_decryption(true)
        .send()
        .await
        .map_err(|error| {
            std::io::Error::other(format!(
                "Failed to read {label} from SSM path {name}: {error}"
            ))
        })?
        .parameter()
        .and_then(|parameter| parameter.value().map(str::to_string))
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| std::io::Error::other(format!("SSM path {name} has no value")).into())
}

pub async fn write_secure_parameter(ssm: &SsmClient, name: &str, value: &str) -> Result<(), Error> {
    ssm.put_parameter()
        .name(name)
        .r#type(ParameterType::SecureString)
        .value(value)
        .overwrite(true)
        .send()
        .await
        .map_err(|error| {
            std::io::Error::other(format!(
                "Failed to write SecureString SSM path {name}: {error}"
            ))
        })?;
    Ok(())
}
