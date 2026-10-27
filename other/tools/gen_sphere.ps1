param([string]$OutputRoot = (Join-Path $PSScriptRoot '..\\..\\datafiles\\demo'))
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

function To-FloatBytes([single[]]$Values) { $m=[IO.MemoryStream]::new(); foreach($v in $Values){$b=[BitConverter]::GetBytes([single]$v);$m.Write($b,0,$b.Length)}; return ,$m.ToArray() }

$lat=16; $lon=24; $r=0.5
# grid of vertices
$grid=@()
for($i=0;$i -le $lat;$i++){
  $theta=[Math]::PI*$i/$lat
  $row=@()
  for($j=0;$j -le $lon;$j++){
    $phi=2.0*[Math]::PI*$j/$lon
    $x=$r*[Math]::Sin($theta)*[Math]::Cos($phi)
    $y=$r*[Math]::Cos($theta)
    $z=$r*[Math]::Sin($theta)*[Math]::Sin($phi)
    $row += ,@($x,$y,$z)
  }
  $grid += ,$row
}

$positions=[Collections.Generic.List[single]]::new()
$normals=[Collections.Generic.List[single]]::new()
$texcoords=[Collections.Generic.List[single]]::new()
for($i=0;$i -lt $lat;$i++){
  for($j=0;$j -lt $lon;$j++){
    $v00=$grid[$i][$j]; $v10=$grid[$i+1][$j]; $v01=$grid[$i][$j+1]; $v11=$grid[$i+1][$j+1]
    # triangle 1: v00, v10, v01
    $t1=@($v00,$v10,$v01); $u1=@($j,$j,($j+1)); $v1=@($i,($i+1),$i)
    for($k=0;$k -lt 3;$k++){ $v=$t1[$k]; $positions.Add([single]$v[0]);$positions.Add([single]$v[1]);$positions.Add([single]$v[2]); $n0=$v[0]/$r;$n1=$v[1]/$r;$n2=$v[2]/$r; $normals.Add([single]$n0);$normals.Add([single]$n1);$normals.Add([single]$n2); $texcoords.Add([single]($u1[$k]/$lon));$texcoords.Add([single]($v1[$k]/$lat)) }
    # triangle 2: v10, v11, v01
    $t2=@($v10,$v11,$v01); $u2=@($j,($j+1),($j+1)); $v2=@(($i+1),($i+1),$i)
    for($k=0;$k -lt 3;$k++){ $v=$t2[$k]; $positions.Add([single]$v[0]);$positions.Add([single]$v[1]);$positions.Add([single]$v[2]); $n0=$v[0]/$r;$n1=$v[1]/$r;$n2=$v[2]/$r; $normals.Add([single]$n0);$normals.Add([single]$n1);$normals.Add([single]$n2); $texcoords.Add([single]($u2[$k]/$lon));$texcoords.Add([single]($v2[$k]/$lat)) }
  }
}
$vc=$positions.Count/3

$bin=[IO.MemoryStream]::new()
function Add-View([byte[]]$Bytes) { while(($bin.Position%4)-ne 0){$bin.WriteByte(0)}; $offset=[int]$bin.Position; $bin.Write($Bytes,0,$Bytes.Length); $v=@{buffer=0;byteOffset=$offset;byteLength=$Bytes.Length};return $v }
$views=[Collections.Generic.List[object]]::new()
$views.Add((Add-View (To-FloatBytes $positions.ToArray())))
$views.Add((Add-View (To-FloatBytes $normals.ToArray())))
$views.Add((Add-View (To-FloatBytes $texcoords.ToArray())))
while(($bin.Position%4)-ne 0){$bin.WriteByte(0)}

$gltf=@{asset=@{version='2.0'};scene=0;scenes=@(@{nodes=@(0)});nodes=@(@{mesh=0});meshes=@(@{primitives=@(@{attributes=@{POSITION=0;NORMAL=1;TEXCOORD_0=2};material=0})});materials=@(@{name='SphereMaterial';pbrMetallicRoughness=@{baseColorFactor=@(0.8,0.8,0.8,1.0);metallicFactor=0.0;roughnessFactor=0.5};doubleSided=$false});accessors=@(@{bufferView=0;componentType=5126;count=$vc;type='VEC3';min=@(-0.5,-0.5,-0.5);max=@(0.5,0.5,0.5)},@{bufferView=1;componentType=5126;count=$vc;type='VEC3'},@{bufferView=2;componentType=5126;count=$vc;type='VEC2'});bufferViews=$views.ToArray();buffers=@(@{byteLength=[int]$bin.Length})}

$json=[Text.Encoding]::UTF8.GetBytes(($gltf|ConvertTo-Json -Depth 20 -Compress));while(($json.Length%4)-ne 0){$json+=0x20};$binary=$bin.ToArray();$total=12+8+$json.Length+8+$binary.Length;$out=[IO.MemoryStream]::new();$w=[IO.BinaryWriter]::new($out);$w.Write([uint32]0x46546C67);$w.Write([uint32]2);$w.Write([uint32]$total);$w.Write([uint32]$json.Length);$w.Write([uint32]0x4E4F534A);$out.Write([byte[]]$json,0,$json.Length);$w.Write([uint32]$binary.Length);$w.Write([uint32]0x004E4942);$out.Write([byte[]]$binary,0,$binary.Length);[IO.File]::WriteAllBytes((Join-Path $OutputRoot 'sphere.glb'),$out.ToArray());Write-Output "Created sphere GLB $($out.Length) bytes"