param([string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\datafiles\demo'))
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

function To-FloatBytes([single[]]$Values) { $m=[IO.MemoryStream]::new(); foreach($v in $Values){$b=[BitConverter]::GetBytes([single]$v);$m.Write($b,0,$b.Length)}; return ,$m.ToArray() }
function To-UShortBytes([uint16[]]$Values) { $m=[IO.MemoryStream]::new(); foreach($v in $Values){$b=[BitConverter]::GetBytes([uint16]$v);$m.Write($b,0,$b.Length)}; return ,$m.ToArray() }
$png=[IO.File]::ReadAllBytes((Join-Path $OutputRoot 'terrain_grass.png'))
$radius=15.0;$segments=64
$positions=[Collections.Generic.List[single]]::new();$normals=[Collections.Generic.List[single]]::new();$uvs=[Collections.Generic.List[single]]::new();$indices=[Collections.Generic.List[uint16]]::new()
$positions.AddRange([single[]]@(0,0,0));$normals.AddRange([single[]]@(0,1,0));$uvs.AddRange([single[]]@(8,8))
for($i=0;$i -lt $segments;$i++){ $a=2.0*[Math]::PI*$i/$segments;$x=[Math]::Cos($a);$z=[Math]::Sin($a);$positions.Add([single]($radius*$x));$positions.Add([single]0);$positions.Add([single]($radius*$z));$normals.AddRange([single[]]@(0,1,0));$uvs.Add([single](8+8*$x));$uvs.Add([single](8+8*$z)) }
for($i=0;$i -lt $segments;$i++){ $cur=[uint16](1+$i);$next=[uint16](1+(($i+1)%$segments));$indices.Add([uint16]0);$indices.Add($next);$indices.Add($cur) }
$bin=[IO.MemoryStream]::new()
function Add-View([byte[]]$Bytes,[int]$Target=-1) { while(($bin.Position%4)-ne 0){$bin.WriteByte(0)}; $offset=[int]$bin.Position; $bin.Write($Bytes,0,$Bytes.Length); $v=@{buffer=0;byteOffset=$offset;byteLength=$Bytes.Length};if($Target -ge 0){$v.target=$Target};return $v }
$views=[Collections.Generic.List[object]]::new()
$views.Add((Add-View (To-FloatBytes $positions.ToArray()) 34962));$views.Add((Add-View (To-FloatBytes $normals.ToArray()) 34962));$views.Add((Add-View (To-FloatBytes $uvs.ToArray()) 34962));$views.Add((Add-View (To-UShortBytes $indices.ToArray()) 34963));$imageViewIndex=$views.Count;$views.Add((Add-View $png));while(($bin.Position%4)-ne 0){$bin.WriteByte(0)}
$gltf=@{asset=@{version='2.0';generator='Polygon demo circular terrain generator'};scene=0;scenes=@(@{nodes=@(0)});nodes=@(@{mesh=0;name='DemoGrassTerrain'});meshes=@(@{name='CircularMeadowMesh';primitives=@(@{attributes=@{POSITION=0;NORMAL=1;TEXCOORD_0=2};indices=3;material=0;mode=4})});materials=@(@{name='Irregular Meadow';pbrMetallicRoughness=@{baseColorTexture=@{index=0};baseColorFactor=@(0.92,0.97,0.88,1.0);metallicFactor=0.0;roughnessFactor=1.0};doubleSided=$true});textures=@(@{sampler=0;source=0});samplers=@(@{magFilter=9729;minFilter=9987;wrapS=10497;wrapT=10497});images=@(@{bufferView=$imageViewIndex;mimeType='image/png';name='Irregular Grass and Soil'});accessors=@(@{bufferView=0;componentType=5126;count=65;type='VEC3';min=@(-15,0,-15);max=@(15,0,15)},@{bufferView=1;componentType=5126;count=65;type='VEC3'},@{bufferView=2;componentType=5126;count=65;type='VEC2';min=@(0,0);max=@(16,16)},@{bufferView=3;componentType=5123;count=192;type='SCALAR';min=@(0);max=@(64)});bufferViews=$views.ToArray();buffers=@(@{byteLength=[int]$bin.Length})}
$json=[Text.Encoding]::UTF8.GetBytes(($gltf|ConvertTo-Json -Depth 20 -Compress));while(($json.Length%4)-ne 0){$json+=0x20};$binary=$bin.ToArray();$total=12+8+$json.Length+8+$binary.Length;$out=[IO.MemoryStream]::new();$w=[IO.BinaryWriter]::new($out);$w.Write([uint32]0x46546C67);$w.Write([uint32]2);$w.Write([uint32]$total);$w.Write([uint32]$json.Length);$w.Write([uint32]0x4E4F534A);$out.Write([byte[]]$json,0,$json.Length);$w.Write([uint32]$binary.Length);$w.Write([uint32]0x004E4942);$out.Write([byte[]]$binary,0,$binary.Length);[IO.File]::WriteAllBytes((Join-Path $OutputRoot 'terrain.glb'),$out.ToArray());Write-Output "Created circular terrain (diameter $($radius*2)m), GLB $($out.Length) bytes"


