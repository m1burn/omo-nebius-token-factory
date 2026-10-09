# VIOLATIONS PLANTED FOR QUALITY-SMOKE (do not fix):
# - PSAvoidUsingConvertToSecureStringWithPlainText: plaintext password converted into a PSCredential
# - PSAvoidUsingInvokeExpression: Invoke-Expression executes a string as code
# - gitleaks generic-api-key: hardcoded password-looking value (fake placeholder, scanners only)
$plainPassword = "Kx9mP2vQ7wLnR4tY8zJb6hFd3sGc5aXe"
$securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential("svc-quality-smoke", $securePassword)
$dynamicCommand = "Get-Process"
Invoke-Expression $dynamicCommand
Write-Output "credential user: $($credential.UserName)"
