//! Registered application schemas keep their own writers and read-only role.
#[cfg(test)]
mod tests;
pub fn default_schemas() -> Vec<String> {
    vec!["public".into()]
}

pub fn identifier(value: &str) -> String {
    format!("\"{}\"", value.replace('"', "\"\""))
}

pub fn grants(schema: &str, writer: &str, reader: &str) -> String {
    let name = identifier(schema);
    let writer = identifier(writer);
    let reader = identifier(reader);
    // Existing registrations retain their public-schema grants. Named schemas
    // start private and are owned by their application writer.
    let create = if schema == "public" {
        String::new()
    } else {
        format!(
            "CREATE SCHEMA IF NOT EXISTS {name} AUTHORIZATION {writer};
             REVOKE ALL ON SCHEMA {name} FROM PUBLIC;"
        )
    };
    format!(
        "{create}
         GRANT ALL ON SCHEMA {name} TO {writer};
         ALTER DEFAULT PRIVILEGES IN SCHEMA {name} GRANT ALL ON TABLES TO {writer};
         ALTER DEFAULT PRIVILEGES IN SCHEMA {name} GRANT ALL ON SEQUENCES TO {writer};
         GRANT ALL ON ALL TABLES IN SCHEMA {name} TO {writer};
         GRANT ALL ON ALL SEQUENCES IN SCHEMA {name} TO {writer};
         GRANT USAGE ON SCHEMA {name} TO {reader};
         GRANT SELECT ON ALL TABLES IN SCHEMA {name} TO {reader};
         GRANT SELECT ON ALL SEQUENCES IN SCHEMA {name} TO {reader};
         ALTER DEFAULT PRIVILEGES IN SCHEMA {name} GRANT SELECT ON TABLES TO {reader};
         ALTER DEFAULT PRIVILEGES IN SCHEMA {name} GRANT SELECT ON SEQUENCES TO {reader};
         ALTER DEFAULT PRIVILEGES FOR ROLE {writer} IN SCHEMA {name} GRANT SELECT ON TABLES TO {reader};
         ALTER DEFAULT PRIVILEGES FOR ROLE {writer} IN SCHEMA {name} GRANT SELECT ON SEQUENCES TO {reader};"
    )
}
