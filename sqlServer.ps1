$apiUrlGetLastEvent = "https://alex666.pythonanywhere.com/api_ultimo_evento"
$apiUrlSendEvents = "https://alex666.pythonanywhere.com/api_guardarCurrent"
$apiUrlSendMachineInfo = "https://alex666.pythonanywhere.com/api_datosMaquina"
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

$headers = @{
    "Content-Type" = "application/json"
}

try {
    $response = Invoke-RestMethod -Uri $apiUrlSendMachineInfo -Method Post -Headers $headers -Body $info_maquina
    $id_maquina = $response.data.id
    if (-not $id_maquina) {
        Write-Error "Error al obtener el ID de la máquina: $response"
        exit
    }
    Write-Output "ID de la máquina: $id_maquina"
} catch {
    Write-Error "Error al enviar los datos de la máquina a la API: $_"
    Write-Error $_.Exception.Message
    if ($_.Exception.Response) {
        $responseStream = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
        $responseBody = $responseStream.ReadToEnd()
        Write-Error "Cuerpo de la respuesta del error: $responseBody"
    }
    exit
}

$eventType = "ErrorLog"

try {
    $bodyUltimoEvento = @{
        id_maquina = $id_maquina
        tipo_evento = $eventType
    } | ConvertTo-Json

    $lastEventResponse = Invoke-RestMethod -Uri $apiUrlGetLastEvent -Method Post -Headers $headers -Body $bodyUltimoEvento
    $lastRecordId = if ($lastEventResponse.code -eq 1) { [long]$lastEventResponse.data.last_record_id } else { 0 }
    Write-Output "Último RecordId: $lastRecordId"
} catch {
    Write-Error "Error al obtener el último RecordId: $_"
    Write-Error $_.Exception.Message
    if ($_.Exception.Response) {
        $responseStream = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
        $responseBody = $responseStream.ReadToEnd()
        Write-Error "Cuerpo de la respuesta del error: $responseBody"
    }
    exit
}

$serverName = $env:COMPUTERNAME
$databaseName = "master"
$connectionString = "Server=$serverName;Database=$databaseName;Integrated Security=True;"

$query = @"
-- Crear una tabla temporal para almacenar los resultados
CREATE TABLE #ErrorLog (
    LogDate DATETIME,
    ProcessInfo NVARCHAR(100),
    Text NVARCHAR(MAX),
    RecordId INT IDENTITY(1,1)
);

-- Insertar los datos del log de errores en la tabla temporal
INSERT INTO #ErrorLog
EXEC xp_readerrorlog 0, 1;

-- Seleccionar registros ordenados por RecordId
SELECT LogDate, ProcessInfo, Text, RecordId
FROM #ErrorLog
WHERE RecordId > $lastRecordId
ORDER BY RecordId ASC;

-- Eliminar la tabla temporal
DROP TABLE #ErrorLog;
"@

try {
    if (-not (Get-Module -ListAvailable -Name SqlServer)) {
        Import-Module SqlServer
    }
    
    $events = Invoke-Sqlcmd -ConnectionString $connectionString -Query $query
    $eventos = @()
    foreach ($event in $events) {
        $eventos += @{
            date = $event.LogDate.ToString("yyyy-MM-ddTHH:mm:ss")
            source = $event.ProcessInfo
            message = $event.Text
            id_maquina = $id_maquina
            recordId = $event.RecordId
        }
    }

    $jsonData = @{
        tipo_evento = $eventType
        id_maquina = $id_maquina
        eventos = $eventos
    } | ConvertTo-Json -Depth 4

    Write-Output "Datos a enviar:"
    Write-Output $jsonData

    $jsonDataBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonData)
    $request = [System.Net.HttpWebRequest]::Create($apiUrlSendEvents)
    $request.Method = "POST"
    $request.ContentType = "application/json"
    $request.ContentLength = $jsonDataBytes.Length
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

    Write-Output "Respuesta de la API:"
    Write-Output $responseBody
} catch {
    Write-Error "Error al enviar los datos a la API: $_"
    Write-Error $_.Exception.Message
    if ($_.Exception.Response) {
        $responseStream = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
        $responseBody = $responseStream.ReadToEnd()
        Write-Error "Cuerpo de la respuesta del error: $responseBody"
    }
    exit
}
