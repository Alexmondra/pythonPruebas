# Verificar si el script se está ejecutando como administrador
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # Re-lanzar el script como administrador
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + $MyInvocation.MyCommand.Path + "`""
    Start-Process powershell -Verb runAs -ArgumentList $arguments
    exit
}

# Define el archivo de log
$logFile = "D:\asd\power_sell\PAF\edit\logfile.log"

# Variable global para almacenar los logs
$global:logEntries = @()

# Función para registrar el estado de los eventos y enviar a la API
function Log-EventStatus {
    param (
        [string]$machineId,
        [string]$eventType,
        [int]$eventCount,
        [string]$status,
        [string]$errorMessage = ""
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - ID Máquina: $machineId, Tipo de Evento: $eventType, Eventos Enviados: $eventCount, Estado: $status"
    if ($status -eq "Error" -or $status -eq "Info") {
        $entry += ", Mensaje: $errorMessage"
    }
    Add-Content -Path $logFile -Value $entry
    
    # Ajustar el valor del mensaje basado en el estado
    $adjustedMessage = if ($status -eq "Success") { "" } else { $errorMessage }

    # Añadir entrada al log para el envío posterior
    $global:logEntries += [PSCustomObject]@{
        timestamp    = $timestamp
        machine_id   = $machineId
        event_type   = $eventType
        event_count  = $eventCount
        status       = $status
        message      = $adjustedMessage
    }
    
    Write-Host "Log agregado: $timestamp, $machineId, $eventType, $eventCount, $status, $adjustedMessage"
}

# Crear el archivo de log si no existe
if (-not (Test-Path $logFile)) {
    New-Item -ItemType File -Path $logFile -Force | Out-Null
    Add-Content -Path $logFile -Value "Archivo de log creado.`n"
}

# Inicio del script principal
try {
    $username = "ivan"
    $password = "1234"

    $body = @{
        username = $username
        password = $password
    } | ConvertTo-Json

    $headers = @{
        "Content-Type" = "application/json"
    }

    try {
        $response = Invoke-RestMethod -Uri "https://alex666.pythonanywhere.com/auth" -Method Post -Headers $headers -Body $body
        $token = $response.access_token
    } catch {
        Log-EventStatus -machineId "Unknown" -eventType "Auth" -eventCount 0 -status "Error" -errorMessage "Credenciales no válidas."
        exit
    }

    $headers = @{
        "Content-Type" = "application/json"
        "Authorization" = "Bearer $token"
    }

    $apiUrlGetLastEvent = "https://alex666.pythonanywhere.com/api_ultimo_evento"
    $apiUrlSendMachineInfo = "https://alex666.pythonanywhere.com/api_datosMaquina"
    $apiUrlSendEvents = @{
        "Application" = "https://alex666.pythonanywhere.com/api_guardarAplicacion"
        "Setup" = "https://alex666.pythonanywhere.com/api_guardarInstalacion"
        "Security" = "https://alex666.pythonanywhere.com/api_guardarSeguridad"
        "System" = "https://alex666.pythonanywhere.com/api_guardarSistema"
    }

    $eventTypes = @("Application", "Setup", "Security", "System")

    $serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
    $sistema_operativo = (Get-WmiObject -Class Win32_OperatingSystem).Caption
    $nombre_maquina = $env:COMPUTERNAME
    $direccion_ip = (Test-Connection -ComputerName $nombre_maquina -Count 1).IPv4Address.IPAddressToString

    $info_maquina = @{
        identificador_unico = $serialNumber
        sistema_operativo = $sistema_operativo
        nombre_maquina = $nombre_maquina
        direccion_ip = $direccion_ip
        descripcion = "Descripción opcional de la máquina"
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri $apiUrlSendMachineInfo -Method Post -Headers $headers -Body $info_maquina
        $id_maquina = $response.data.id
        if (-not $id_maquina) {
            Log-EventStatus -machineId "Unknown" -eventType "MachineInfo" -eventCount 0 -status "Error" -errorMessage "Error al obtener el ID de la máquina."
            exit
        }
    } catch {
        Log-EventStatus -machineId "Unknown" -eventType "MachineInfo" -eventCount 0 -status "Error" -errorMessage $_.Exception.Message
        exit
    }

    foreach ($eventType in $eventTypes) {
        try {
            $bodyUltimoEvento = @{
                id_maquina = $id_maquina
                tipo_evento = $eventType
            } | ConvertTo-Json

            $lastEventResponse = Invoke-RestMethod -Uri $apiUrlGetLastEvent -Method Post -Headers $headers -Body $bodyUltimoEvento
            $lastRecordId = if ($lastEventResponse.code -eq 1) { [long]$lastEventResponse.data.last_record_id } else { 0 }

            $currentLastRecordId = (Get-WinEvent -LogName $eventType -MaxEvents 1 | Measure-Object -Property RecordId -Maximum).Maximum

            if ($lastRecordId -eq $currentLastRecordId) {
                Log-EventStatus -machineId $id_maquina -eventType $eventType -eventCount 0 -status "Info" -errorMessage "Datos actualizados."
                continue
            }
        } catch {
            Log-EventStatus -machineId $id_maquina -eventType $eventType -eventCount 0 -status "Error" -errorMessage $_.Exception.Message
            continue
        }

        try {
            $events = if ($lastRecordId -eq 0) {
                Get-WinEvent -LogName $eventType -ErrorAction SilentlyContinue | Select-Object -Property Id, LevelDisplayName, TimeCreated, ProviderName, RecordId, Message -First 10
            } else {
                Get-WinEvent -LogName $eventType -ErrorAction SilentlyContinue | Where-Object { $_.RecordId -gt $lastRecordId } | Select-Object -Property Id, LevelDisplayName, TimeCreated, ProviderName, RecordId, Message -First 10
            }

            $eventos = @()
            foreach ($event in $events) {
                $eventObject = @{
                    fechaHora = $event.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss")
                    origen = $event.ProviderName
                    idEvento = $event.Id
                    recordId = $event.RecordId
                    categoriaTarea = $null
                    id_maquina = $id_maquina
                    tipo_evento = $eventType
                }

                if ($eventType -eq "Security") {
                    $eventObject += @{
                        palabraClave = $event.Message
                    }
                } else {
                    $eventObject += @{
                        nivel = $event.LevelDisplayName
                    }
                }

                $eventos += $eventObject
            }

            $jsonData = @{
                tipo_evento = $eventType
                id_maquina = $id_maquina
                eventos = $eventos
            } | ConvertTo-Json -Depth 4

            try {
                $jsonDataBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonData)
                $request = [System.Net.HttpWebRequest]::Create($apiUrlSendEvents[$eventType])
                $request.Method = "POST"
                $request.ContentType = "application/json"
                $request.ContentLength = $jsonDataBytes.Length
                $request.Headers.Add("Authorization", "Bearer $token")
                $requestStream = $request.GetRequestStream()
                $requestStream.Write($jsonDataBytes, 0, $jsonDataBytes.Length)
                $requestStream.Close()

                $response = $request.GetResponse()
                $responseStream = $response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($responseStream)
                $responseBody = $reader.ReadToEnd()
                $reader.Close()
                $responseStream.Close()
                $response.Close()

                Log-EventStatus -machineId $id_maquina -eventType $eventType -eventCount $eventos.Count -status "Success" -errorMessage $responseBody
            } catch {
                Log-EventStatus -machineId $id_maquina -eventType $eventType -eventCount $eventos.Count -status "Error" -errorMessage $_.Exception.Message
                continue
            }
        } catch {
            Log-EventStatus -machineId $id_maquina -eventType $eventType -eventCount 0 -status "Error" -errorMessage $_.Exception.Message
            continue
        }
    }

    # Verificar la cantidad de logs
    Write-Host "Cantidad de logs en logEntries: $($global:logEntries.Count)"

    # Enviar todos los logs acumulados a la API
    if ($global:logEntries.Count -gt 0) {
        $logJson = @{
            eventos = $global:logEntries
        } | ConvertTo-Json -Depth 4

        $logRequestHeaders = @{
            "Content-Type" = "application/json"
        }

        Write-Host "Enviando eventos: $logJson"

        try {
            $logResponse = Invoke-RestMethod -Uri "https://alex666.pythonanywhere.com/api/logs" -Method Post -Headers $logRequestHeaders -Body $logJson
            Write-Output "Respuesta del servidor de logs: $logResponse"
        } catch {
            Write-Error "Error al enviar los logs a la API: $_"
            if ($_.Exception.Response) {
                $responseStream = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                $responseBody = $responseStream.ReadToEnd()
                Write-Host "Cuerpo de la respuesta del error: $responseBody"
            }
        }
    } else {
        Write-Host "No se encontraron logs para enviar."
        Write-Host "Contenido de logEntries: $($global:logEntries | ConvertTo-Json -Depth 4)"
    }

} catch {
    Log-EventStatus -machineId "Unknown" -eventType "General" -eventCount 0 -status "Error" -errorMessage $_.Exception.Message
}

exit
