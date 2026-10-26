param([string]$OutputRoot = (Join-Path $PSScriptRoot '..\\..\\datafiles\\demo'))
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

function To-FloatBytes([single[]]$Values) { $m=[IO.MemoryStream]::new(); foreach($v in $Values){$b=[BitConverter]::GetBytes([single]$v);$m.Write($b,0,$b.Length)}; return ,$m.ToArray() }

$faces = @(
 @(-0.5,-0.5,-0.5, 0.5,-0.5,-0.5, 0.5,0.5,-0.5,  0,0,-1),
 @(-0.5,-0.5,-0.5, 0.5,0.5,-0.5, -0.5,0.5,-0.5,  0,0,-1),
 @(-0.5,-0.5,0.5, 0.5,0.5,0.5, 0.5,-0.5,0.5,  0,0,1),
 @(-0.5,-0.5,0.5, -0.5,0.5,0.5, 0.5,0.5,0.5,  0,0,1),
 @(-0.5,-0.5,-0.5, -0.5,-0.5,0.5, 0.5,-0.5,0.5,  0,-1,0),
 @(-0.5,-0.5,-0.5, 0.5,-0.5,0.5, 0.5,-0.5,-0.5,  0,-1,0),
 @(-0.5,0.5,-0.5, 0.5,0.5,-0.5, 0.5,0.5,0.5,  0,1,0),
 @(-0.5,0.5,-0.5, 0.5,0.5,0.5, -0.5,0.5,0.5,  0,1,0),
 @(-0.5,-0.5,-0.5, -0.5,0.5,-0.5, -0.5,0.5,0.5, -1,0,0),
 @(-0.5,-0.5,-0.5, -0.5,0.5,0.5, -0.5,-0.5,0.5, -1,0,0),
 @(0.5,-0.5,-0.5, 0.5,-0.5,0.5, 0.5,0.5,0.5,  1,0,0),
 @(0.5,-0.5,-0.5, 0.5,0.5,0.5, 0.5,0.5,-0.5,  1,0,0)
)
$positions=[Collections.Generic.List[single]]::new()
$normals=[Collections.Generic.List[single]]::new()
foreach($f in $faces){
  for($k=0;$k -lt 3;$k++){
    $vi = 2 - $k
    $positions.Add([single]$f[$vi*3]); $positions.Add([single]$f[$vi*3+1]); $positions.Add([single]$f[$vi*3+2])
    $normals.Add([single]$f[9]); $normals.Add([single]$f[10]); $normals.Add([single]$f[11])
  }
}
$vc=$positions.Count/3

$bin=[IO.MemoryStream]::new()
function Add-View([byte[]]$Bytes) { while(($bin.Position%4)-ne 0){$bin.WriteByte(0)}; $offset=[int]$bin.Position; $bin.Write($Bytes,0,$Bytes.Length); $v=@{buffer=0;byteOffset=$offset;byteLength=$Bytes.Length};return $v }
$views=[Collections.Generic.List[object]]::new()
$views.Add((Add-View (To-FloatBytes $positions.ToArray())))
$views.Add((Add-View (To-FloatBytes $normals.ToArray())))
while(($bin.Position%4)-ne 0){$bin.WriteByte(0)}

$gltf=@{asset=@{version='2.0'};scene=0;scenes=@(@{nodes=@(0)});nodes=@(@{mesh=0});meshes=@(@{primitives=@(@{attributes=@{POSITION=0;NORMAL=1}})});accessors=@(@{bufferView=0;componentType=5126;count=$vc;type='VEC3';min=@(-0.5,-0.5,-0.5);max=@(0.5,0.5,0.5)},@{bufferView=1;componentType=5126;count=$vc;type='VEC3'});bufferViews=$views.ToArray();buffers=@(@{byteLength=[int]$bin.Length})}

$json=[Text.Encoding]::UTF8.GetBytes(($gltf|ConvertTo-Json -Depth 20 -Compress));while(($json.Length%4)-ne 0){$json+=0x20};$binary=$bin.ToArray();$total=12+8+$json.Length+8+$binary.Length;$out=[IO.MemoryStream]::new();$w=[IO.BinaryWriter]::new($out);$w.Write([uint32]0x46546C67);$w.Write([uint32]2);$w.Write([uint32]$total);$w.Write([uint32]$json.Length);$w.Write([uint32]0x4E4F534A);$out.Write([byte[]]$json,0,$json.Length);$w.Write([uint32]$binary.Length);$w.Write([uint32]0x004E4942);$out.Write([byte[]]$binary,0,$binary.Length);[IO.File]::WriteAllBytes((Join-Path $OutputRoot 'cube.glb'),$out.ToArray());Write-Output "Created cube GLB $($out.Length) bytes"