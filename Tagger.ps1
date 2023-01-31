$client = @{
    IP       = '192.168.0.50'
    Port     = '8080'
    login    = 'admin'
    password = 'mainstreet'
}
$label = 'Личное'

Add-Type -AssemblyName System.Windows.Forms
$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$OpenFileDialog.InitialDirectory = $PSScriptRoot
$OpenFileDialog.Title = "Файл со списком ID"
$OpenFileDialog.filter = “TXT files| *.txt”
If ($OpenFileDialog.ShowDialog() -eq "Cancel") {
    [System.Windows.Forms.MessageBox]::Show("Вы ничего не выбрали!", "Error", 0, 
        [System.Windows.Forms.MessageBoxIcon]::Exclamation)
    exit
}
$ids = Get-Content -Path $OpenFileDialog.FileName
If ( $ids.count -eq 0 ) {
    Write-Host 'В файле не найлено ID, выходим'
    Exit
}
Write-Host ( 'В файле найдено ' + $ids.count + ' ID' )
if ( !$client.sid ) {
    $logindata = @{
        username = $client.login
        password = $client.password
    }
    $loginheader = @{ Referer = 'http://' + $client.IP + ':' + $client.Port }
    try {
        Write-Host ( 'Авторизуемся в клиенте ' + $client.Name )
        $url = $client.IP + ':' + $client.Port + '/api/v2/auth/login'
        $result = Invoke-WebRequest -Method POST -Uri $url -Headers $loginheader -Body $logindata -SessionVariable sid
        if ( $result.StatusCode -ne 200 ) { throw 'You are banned.' }
        if ( $result.Content -ne 'Ok.') { throw $result.Content }
        $client.sid = $sid
    }
    catch { Write-Host ( 'Не удалось авторизоваться в клиенте, прерываем. Ошибка: {0}.' -f $Error[0] ) -ForegroundColor Red; Exit }
}
Write-Host 'Получаем список раздач от клиента'
try { $torrents_list = ( Invoke-WebRequest -uri ( $client.ip + ':' + $client.Port + '/api/v2/torrents/info' ) -WebSession $client.sid ).Content | ConvertFrom-Json | Select-Object hash }
catch { Write-Host 'Не удалось получить список раздач из клиента'; exit }
If ( $torrents_list.count -eq 0 ) {
    Write-Host 'В файле не найлено ID, выходим'
    Exit
}
Write-Host 'Получаем ID и сверяем со списком'
$tag_url = $client.IP + ':' + $client.Port + '/api/v2/torrents/addTags'
foreach ( $torrent in $torrents_list) {
    $Params = @{ hash = $torrent.hash }
    $cl_id = ( ( Invoke-WebRequest -uri ( $client.ip + ':' + $client.Port + '/api/v2/torrents/properties' ) -WebSession $client.sid -Body $params ).Content | `
        ConvertFrom-Json | Select-Object comment -ExpandProperty comment | select-string ('\d+$')).matches[0].Value
    if ( $cl_id -in $ids ) {
        $tag_body = @{ hashes = $torrent.hash; tags = $label }
        Invoke-WebRequest -Method POST -Uri $tag_url -Headers $loginheader -Body $tag_body -WebSession $client.sid | Out-Null
        $ids = $ids | Where-Object { $_ -ne $cl_id }
        if ( $ids.count -eq 0 ) {
            Write-Host 'Вроде, всё'
            Exit
        }
    }
}