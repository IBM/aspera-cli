# Chocolatey

## todo

Packing:

```shell
nuget pack ascli.nuspec -OutputDirectory ../../pkg
```

## Procedure

Get an API Key

- Sign in to Chocolatey Community Repository.
- Go to Account Settings → API Keys.
- Copy your API key.

```powershell
choco apikey --key <YOUR_API_KEY> --source https://push.chocolatey.org/
```
