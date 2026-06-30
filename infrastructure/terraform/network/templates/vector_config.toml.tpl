data_dir = "/var/lib/vector"

%{ for idx, log in file_logs ~}
[sources.file_${idx}]
type = "file"
include = ["${log.file_path}"]
read_from = "beginning"

[sinks.file_${idx}_cloudwatch]
type = "aws_cloudwatch_logs"
inputs = ["file_${idx}"]
group_name = "${log.log_group_name}"
stream_name = "${replace(log.log_stream_name, "{instance_id}", "$${INSTANCE_ID}")}"
region = "$${AWS_REGION}"

[sinks.file_${idx}_cloudwatch.encoding]
codec = "text"

%{ endfor ~}
%{ for idx, log in journal_logs ~}
[sources.journald_${idx}]
type = "journald"
%{ if log.match_field == "SYSTEMD_UNIT" }
include_units = [${jsonencode(log.match_value)}]
%{ else }
include_matches.${log.match_field} = [${jsonencode(log.match_value)}]
%{ endif }

[sinks.journald_${idx}_cloudwatch]
type = "aws_cloudwatch_logs"
inputs = ["journald_${idx}"]
group_name = "${log.log_group_name}"
stream_name = "${replace(log.log_stream_name, "{instance_id}", "$${INSTANCE_ID}")}"
region = "$${AWS_REGION}"

[sinks.journald_${idx}_cloudwatch.encoding]
codec = "text"

%{ endfor ~}
