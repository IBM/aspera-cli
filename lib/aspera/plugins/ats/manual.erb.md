## Plugin: `ats`: IBM Aspera Transfer Service

ATS is usable either:

- From an AoC subscription: `<%=cmd%> aoc admin ats`: use AoC authentication

- Or from an IBM Cloud subscription: `<%=cmd%> ats`: use IBM Cloud API key authentication

### IBM Cloud ATS: Creation of API key

> [!NOTE]
> If you are using ATS as part of AoC, then authentication is through AoC, not IBM Cloud.
> See the AoC section instead.

This section is about using ATS with an IBM Cloud subscription.

First get your IBM Cloud API key.
For instance, it can be created using the IBM Cloud web interface, or using command line:

```shell
ibmcloud iam api-key-create <%=ph :key_name%> -d '<%=ph :description%>'
```

```text
OK
API key <%=ph :key_name%> was created

Please preserve the API key! It cannot be retrieved after it's created.

Name          <%=ph :key_name%>
Description   <%=ph :description%>
Created At    2019-09-30T12:17+0000
API Key       <%=ph :api_key%>
Locked        false
UUID          ApiKey-05b8fadf-e7fe-abcd-93a9-6fd348c5ab1f
```

References:
<!-- spellchecker: disable -->

- [IBM Cloud Managing user API keys](https://cloud.ibm.com/docs/account?topic=account-userapikey&interface=cli)
- [IBM Aspera on Cloud regions](https://ibmaspera.com/help/cloud_platforms_and_regions_supported)

<!-- spellchecker: enable -->

Then, to register the key by default for the `ats` plugin, create a preset.
Execute:

```shell
<%=cmd%> config preset set <%=ph :preset_name%> @: ibm_api_key=<%=ph :api_key%>
```

```shell
<%=cmd%> config preset set default ats <%=ph :preset_name%>
```

```shell
<%=cmd%> ats api_key instances
```

```text
aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
```

```shell
<%=cmd%> config preset set <%=ph :preset_name%> @: instance=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
```

```shell
<%=cmd%> ats api_key create --out.secrets=yes
```

```text
╭────────┬──────────────╮
│ field  │ value        │
╞════════╪══════════════╡
│ id     │ <%=ph :ats_key%>    │
│ secret │ <%=ph :ats_secret%> │
╰────────┴──────────────╯
```

```shell
<%=cmd%> config preset set <%=ph :preset_name%> @: ats_key=<%=ph :ats_key%> ats_secret=<%=ph :ats_secret%>
```

### ATS Access key creation parameters

When creating an ATS access key, the creation parameters are provided as a positional argument of `access_key create`, as a `Hash` [Extended Value](#extended-value-syntax).
If key `transfer_server_id` is not provided, the transfer server is selected with options `cloud` and `region`.
Those are directly the parameters expected by the [ATS API](https://developer.ibm.com/apis/catalog?search=%22Aspera%20ATS%20API%22).

### Misc. Examples

Example: create access key on IBM Cloud (Softlayer):

```shell
<%=cmd%> ats access_key create @json:'{"storage":{"type":"softlayer_swift","container":"_container_name_","credentials":{"api_key":"<%=ph :secret%>","username":"_name_:_usr_name_"},"path":"/"},"id":"_optional_id_","name":"_optional_name_"}' --cloud=softlayer --region=ams
```

Example: create access key on AWS:

```shell
<%=cmd%> ats access_key create @json:'{"id":"<%=ph :access_key%>","name":"laurent key AWS","storage":{"type":"aws_s3","bucket":"my-bucket","credentials":{"access_key_id":"<%=ph :access_key_id%>","secret_access_key":"<%=ph :secret%>"},"path":"/laurent"}}' --cloud=aws --region=eu-west-1
```

Example: create access key on Azure SAS:

```shell
<%=cmd%> ats access_key create @json:'{"id":"<%=ph :access_key%>","name":"laurent key azure","storage":{"type":"azure_sas","credentials":{"shared_access_signature":"https://containername.blob.core.windows.net/blobname?sr=c&..."},"path":"/"}}' --cloud=azure --region=eastus
```

> [!NOTE]
> The blob name is mandatory after the server address and before the parameters, and parameter `sr=c` is mandatory.

Example: create access key on Azure:

```shell
<%=cmd%> ats access_key create @json:'{"id":"<%=ph :access_key%>","name":"laurent key azure","storage":{"type":"azure","credentials":{"account":"myaccount","key":"<%=ph :access_key%>","storage_endpoint":"myblob"},"path":"/"}}' --cloud=azure --region=eastus
```

Delete all access keys:

```shell
<%=cmd%> ats access_key list --fields=id --format=csv | <%=cmd%> ats access_key delete @lines:@stdin: --bulk=yes
```

The parameters provided to ATS for access key creation are the ones of [ATS API](https://developer.ibm.com/apis/catalog?search=%22aspera%20ats%22) for the `POST /access_keys` endpoint.

<%=include_commands_for_plugin(:ats)%>

