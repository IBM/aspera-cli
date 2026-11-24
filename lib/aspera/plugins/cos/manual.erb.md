## Plugin: `cos`: IBM Cloud Object Storage

IBM Cloud Object Storage supports high-speed transfers using the FASP protocol.
These transfers leverage the same service used by Aspera on Cloud, called the Aspera Transfer Service (ATS).
You can check the list of available ATS regions here: <https://status.aspera.io>.
There are two ways to provide credentials:

- Using existing credentials

  If you already have the endpoint, API key, and Resource Instance ID (CRN), use this method.

- Using IBM Cloud Console access

  If you do not have credentials but have access to the IBM Cloud Console, use this alternative method.

### Using endpoint, API key and Resource Instance ID (CRN)

If you already have these parameters, provide the following options to <%=tool%>:

| Option     | Description                                       |
|------------|---------------------------------------------------|
| `bucket`   | Bucket name                                       |
| `endpoint` | Storage endpoint URL<%=br%>for example, `https://s3.hkg02.cloud-object-storage.appdomain.cloud` |
| `apikey`   | API Key                                           |
| `crn`      | Resource instance ID                              |

Example: Create a Default Configuration

```shell
<%=cmd%> config preset set <%=ph :cos_preset_name%> @: bucket=mybucket endpoint=https://s3.us-east.cloud-object-storage.appdomain.cloud apikey=<%=ph :api_key%> crn=<%=ph :crn%>
<%=cmd%> config preset set default cos <%=ph :cos_preset_name%>
```

Once configured, proceed to the [transfer example](#operations-transfers).

### Using service credential file

If you are the COS administrator and do not yet have credentials,
you can create them directly from the IBM Cloud Console (Web UI):

Steps:

- &rarr; Navigation Menu
- &rarr; [Resource List](https://cloud.ibm.com/resources)
- &rarr; [Storage](https://cloud.ibm.com/objectstorage)
- &rarr; Select your storage instance
- &rarr; Service Credentials
- &rarr; New credentials (Leave default role: Writer, no special options)
- &rarr; Copy to clipboard

Save the copied JSON value to a file, for example: `$HOME/cos_service_creds.json`

Or, using the IBM Cloud CLI:

```shell
ibmcloud resource service-keys
ibmcloud resource service-key <%=ph :service_key_name%> --output JSON|jq '.[0].credentials'>$HOME/service_creds.json
```

> [!NOTE]
> If `jq` is not installed, you can manually extract the credentials section from the JSON output.

The service credential file consists of the following structure:

```json
{
  "apikey": "<%=ph :api_key%>",
  "cos_hmac_keys": {
    "access_key_id": "<%=ph :access_key%>",
    "secret_access_key": "<%=ph :secret%>"
  },
  "endpoints": "https://control.cloud-object-storage.cloud.ibm.com/v2/endpoints",
  "iam_apikey_description": "<%=ph :description%>",
  "iam_apikey_name": "<%=ph :name%>",
  "iam_role_crn": "crn:v1:bluemix:public:iam::::serviceRole:Writer",
  "iam_serviceid_crn": "crn:v1:bluemix:public:iam-identity::a/xxxxxxx.....",
  "resource_instance_id": "crn:v1:bluemix:public:cloud-object-storage:global:a/xxxxxxx....."
}
```

The field mappings are as follows:

- `resource_instance_id` &rarr; option `crn`
- `apikey` &rarr; option `apikey`

> [!NOTE]
> Endpoints for regions can be found by querying the `endpoints` URL in the JSON file or from the IBM Cloud Console.

The required options for this method are:

| Option                | Description                                    |
|-----------------------|------------------------------------------------|
| `bucket`              | Bucket name                                    |
| `region`              | Bucket region<%=br%>for example, `eu-de`               |
| `service_credentials` | JSON information saved from IBM Cloud console. |

Example: Create a Default Configuration

```shell
<%=cmd%> config preset set <%=ph :cos_preset_name%> @: bucket=mybucket service_credentials=@val:@json:@file:~/service_creds.json region=us-south
<%=cmd%> config preset set default cos <%=ph :cos_preset_name%>
```

### Operations, transfers

After creating a default configuration using one of the previous methods (otherwise, specify the access options directly on the command line), you can perform a subset of `node` plugin operations, which correspond to the Node API.

```shell
<%=cmd%> cos node info
<%=cmd%> cos node upload 'faux:///sample1G?1g'
```

> [!NOTE]
> The file `sample1G` is a dummy file of size 1 GiB, generated using the `faux` PVCL scheme (see previous section and `man ascp`).
> To upload a real file, replace the `faux:///...` URI with the actual file path.

<%=include_commands_for_plugin(:cos)%>

