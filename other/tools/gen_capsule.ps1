param([string]$OutputRoot = (Join-Path $PSScriptRoot '..\\..\\datafiles\\demo'))
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

function To-FloatBytes([single[]]$Values) { $m=[IO.MemoryStream]::new(); foreach($v in $Values){$b=[BitConverter]::GetBytes([single]$v);$m.Write($b,0,$b.Length)}; return ,$m.ToArray() }

$segs=24; $r=0.25; $h=0.5; $hh=$h/2
$vh=$hh+$r
$positions=[Collections.Generic.List[single]]::new()
$normals=[Collections.Generic.List[single]]::new()
$texcoords=[Collections.Generic.List[single]]::new()

for($i=0;$i -lt $segs;$i++){
  $a1=2.0*[Math]::PI*$i/$segs; $a2=2.0*[Math]::PI*($i+1)/$segs
  $x1=$r*[Math]::Cos($a1); $z1=$r*[Math]::Sin($a1)
  $x2=$r*[Math]::Cos($a2); $z2=$r*[Math]::Sin($a2)
  $n1x=[Math]::Cos($a1); $n1z=[Math]::Sin($a1)
  $n2x=[Math]::Cos($a2); $n2z=[Math]::Sin($a2)
  $u1=$i/$segs; $u2=($i+1)/$segs
  $vLo=($vh+$hh)/(2*$vh); $vHi=($vh-$hh)/(2*$vh)
  $positions.Add([single]$x1);$positions.Add([single](-$hh));$positions.Add([single]$z1)
  $positions.Add([single]$x2);$positions.Add([single](-$hh));$positions.Add([single]$z2)
  $positions.Add([single]$x1);$positions.Add([single]$hh);$positions.Add([single]$z1)
  $normals.Add([single]$n1x);$normals.Add([single]0);$normals.Add([single]$n1z)
  $normals.Add([single]$n2x);$normals.Add([single]0);$normals.Add([single]$n2z)
  $normals.Add([single]$n1x);$normals.Add([single]0);$normals.Add([single]$n1z)
  $texcoords.Add([single]$u1);$texcoords.Add([single]$vLo);$texcoords.Add([single]$u2);$texcoords.Add([single]$vLo);$texcoords.Add([single]$u1);$texcoords.Add([single]$vHi)
  $positions.Add([single]$x2);$positions.Add([single](-$hh));$positions.Add([single]$z2)
  $positions.Add([single]$x2);$positions.Add([single]$hh);$positions.Add([single]$z2)
  $positions.Add([single]$x1);$positions.Add([single]$hh);$positions.Add([single]$z1)
  $normals.Add([single]$n2x);$normals.Add([single]0);$normals.Add([single]$n2z)
  $normals.Add([single]$n2x);$normals.Add([single]0);$normals.Add([single]$n2z)
  $normals.Add([single]$n1x);$normals.Add([single]0);$normals.Add([single]$n1z)
  $texcoords.Add([single]$u2);$texcoords.Add([single]$vLo);$texcoords.Add([single]$u2);$texcoords.Add([single]$vHi);$texcoords.Add([single]$u1);$texcoords.Add([single]$vHi)
}
$latH=8
for($i=0;$i -lt $latH;$i++){
  $t1=[Math]::PI/2*$i/$latH; $t2=[Math]::PI/2*($i+1)/$latH
  for($j=0;$j -lt $segs;$j++){
    $p1=2.0*[Math]::PI*$j/$segs; $p2=2.0*[Math]::PI*($j+1)/$segs
    $sinT1=[Math]::Sin($t1); $cosT1=[Math]::Cos($t1)
    $sinT2=[Math]::Sin($t2); $cosT2=[Math]::Cos($t2)
    $cosP1=[Math]::Cos($p1); $sinP1=[Math]::Sin($p1)
    $cosP2=[Math]::Cos($p2); $sinP2=[Math]::Sin($p2)
    $v00x=$r*$sinT1*$cosP1; $v00y=$hh+$r*$cosT1; $v00z=$r*$sinT1*$sinP1
    $v10x=$r*$sinT2*$cosP1; $v10y=$hh+$r*$cosT2; $v10z=$r*$sinT2*$sinP1
    $v01x=$r*$sinT1*$cosP2; $v01y=$hh+$r*$cosT1; $v01z=$r*$sinT1*$sinP2
    $v11x=$r*$sinT2*$cosP2; $v11y=$hh+$r*$cosT2; $v11z=$r*$sinT2*$sinP2
    $positions.Add([single]$v00x);$positions.Add([single]$v00y);$positions.Add([single]$v00z)
    $positions.Add([single]$v10x);$positions.Add([single]$v10y);$positions.Add([single]$v10z)
    $positions.Add([single]$v01x);$positions.Add([single]$v01y);$positions.Add([single]$v01z)
    $normals.Add([single]($v00x/$r));$normals.Add([single](($v00y-$hh)/$r));$normals.Add([single]($v00z/$r))
    $normals.Add([single]($v10x/$r));$normals.Add([single](($v10y-$hh)/$r));$normals.Add([single]($v10z/$r))
    $normals.Add([single]($v01x/$r));$normals.Add([single](($v01y-$hh)/$r));$normals.Add([single]($v01z/$r))
    $tu1=$j/$segs; $tu2=($j+1)/$segs
    $texcoords.Add([single]$tu1);$texcoords.Add([single](($vh-$v00y)/(2*$vh)));$texcoords.Add([single]$tu1);$texcoords.Add([single](($vh-$v10y)/(2*$vh)));$texcoords.Add([single]$tu2);$texcoords.Add([single](($vh-$v01y)/(2*$vh)))
    $positions.Add([single]$v10x);$positions.Add([single]$v10y);$positions.Add([single]$v10z)
    $positions.Add([single]$v11x);$positions.Add([single]$v11y);$positions.Add([single]$v11z)
    $positions.Add([single]$v01x);$positions.Add([single]$v01y);$positions.Add([single]$v01z)
    $normals.Add([single]($v10x/$r));$normals.Add([single](($v10y-$hh)/$r));$normals.Add([single]($v10z/$r))
    $normals.Add([single]($v11x/$r));$normals.Add([single](($v11y-$hh)/$r));$normals.Add([single]($v11z/$r))
    $normals.Add([single]($v01x/$r));$normals.Add([single](($v01y-$hh)/$r));$normals.Add([single]($v01z/$r))
    $texcoords.Add([single]$tu1);$texcoords.Add([single](($vh-$v10y)/(2*$vh)));$texcoords.Add([single]$tu2);$texcoords.Add([single](($vh-$v11y)/(2*$vh)));$texcoords.Add([single]$tu2);$texcoords.Add([single](($vh-$v01y)/(2*$vh)))
  }
}
# bottom hemisphere
for($i=0;$i -lt $latH;$i++){
  $t1=[Math]::PI/2 + [Math]::PI/2*$i/$latH; $t2=[Math]::PI/2 + [Math]::PI/2*($i+1)/$latH
  for($j=0;$j -lt $segs;$j++){
    $p1=2.0*[Math]::PI*$j/$segs; $p2=2.0*[Math]::PI*($j+1)/$segs
    $sinT1=[Math]::Sin($t1); $cosT1=[Math]::Cos($t1)
    $sinT2=[Math]::Sin($t2); $cosT2=[Math]::Cos($t2)
    $cosP1=[Math]::Cos($p1); $sinP1=[Math]::Sin($p1)
    $cosP2=[Math]::Cos($p2); $sinP2=[Math]::Sin($p2)
    $v00x=$r*$sinT1*$cosP1; $v00y=-$hh+$r*$cosT1; $v00z=$r*$sinT1*$sinP1
    $v10x=$r*$sinT2*$cosP1; $v10y=-$hh+$r*$cosT2; $v10z=$r*$sinT2*$sinP1
    $v01x=$r*$sinT1*$cosP2; $v01y=-$hh+$r*$cosT1; $v01z=$r*$sinT1*$sinP2
    $v11x=$r*$sinT2*$cosP2; $v11y=-$hh+$r*$cosT2; $v11z=$r*$sinT2*$sinP2
    $positions.Add([single]$v00x);$positions.Add([single]$v00y);$positions.Add([single]$v00z)
    $positions.Add([single]$v10x);$positions.Add([single]$v10y);$positions.Add([single]$v10z)
    $positions.Add([single]$v01x);$positions.Add([single]$v01y);$positions.Add([single]$v01z)
    $normals.Add([single]($v00x/$r));$normals.Add([single](($v00y+$hh)/$r));$normals.Add([single]($v00z/$r))
    $normals.Add([single]($v10x/$r));$normals.Add([single](($v10y+$hh)/$r));$normals.Add([single]($v10z/$r))
    $normals.Add([single]($v01x/$r));$normals.Add([single](($v01y+$hh)/$r));$normals.Add([single]($v01z/$r))
    $tu1=$j/$segs; $tu2=($j+1)/$segs
    $texcoords.Add([single]$tu1);$texcoords.Add([single](($vh-$v00y)/(2*$vh)));$texcoords.Add([single]$tu1);$texcoords.Add([single](($vh-$v10y)/(2*$vh)));$texcoords.Add([single]$tu2);$texcoords.Add([single](($vh-$v01y)/(2*$vh)))
    $positions.Add([single]$v10x);$positions.Add([single]$v10y);$positions.Add([single]$v10z)
    $positions.Add([single]$v11x);$positions.Add([single]$v11y);$positions.Add([single]$v11z)
    $positions.Add([single]$v01x);$positions.Add([single]$v01y);$positions.Add([single]$v01z)
    $normals.Add([single]($v10x/$r));$normals.Add([single](($v10y+$hh)/$r));$normals.Add([single]($v10z/$r))
    $normals.Add([single]($v11x/$r));$normals.Add([single](($v11y+$hh)/$r));$normals.Add([single]($v11z/$r))
    $normals.Add([single]($v01x/$r));$normals.Add([single](($v01y+$hh)/$r));$normals.Add([single]($v01z/$r))
    $texcoords.Add([single]$tu1);$texcoords.Add([single](($vh-$v10y)/(2*$vh)));$texcoords.Add([single]$tu2);$texcoords.Add([single](($vh-$v11y)/(2*$vh)));$texcoords.Add([single]$tu2);$texcoords.Add([single](($vh-$v01y)/(2*$vh)))
  }
}
$revPos=[Collections.Generic.List[single]]::new()
$revNrm=[Collections.Generic.List[single]]::new()
$revUV=[Collections.Generic.List[single]]::new()
for($i=0;$i -lt $positions.Count; $i+=9){
  for($k=2;$k -ge 0;$k--){
    $revPos.Add($positions[$i+$k*3]); $revPos.Add($positions[$i+$k*3+1]); $revPos.Add($positions[$i+$k*3+2])
    $revNrm.Add($normals[$i+$k*3]); $revNrm.Add($normals[$i+$k*3+1]); $revNrm.Add($normals[$i+$k*3+2])
    $uvBase=[int](($i/3)+$k)*2; $revUV.Add($texcoords[$uvBase]); $revUV.Add($texcoords[$uvBase+1])
  }
}
$positions=$revPos; $normals=$revNrm; $texcoords=$revUV
$vc=$positions.Count/3

$bin=[IO.MemoryStream]::new()
function Add-View([byte[]]$Bytes) { while(($bin.Position%4)-ne 0){$bin.WriteByte(0)}; $offset=[int]$bin.Position; $bin.Write($Bytes,0,$Bytes.Length); $v=@{buffer=0;byteOffset=$offset;byteLength=$Bytes.Length};return $v }
$views=[Collections.Generic.List[object]]::new()
$views.Add((Add-View (To-FloatBytes $positions.ToArray())))
$views.Add((Add-View (To-FloatBytes $normals.ToArray())))
$views.Add((Add-View (To-FloatBytes $texcoords.ToArray())))
while(($bin.Position%4)-ne 0){$bin.WriteByte(0)}

$gltf=@{asset=@{version='2.0'};scene=0;scenes=@(@{nodes=@(0)});nodes=@(@{mesh=0});meshes=@(@{primitives=@(@{attributes=@{POSITION=0;NORMAL=1;TEXCOORD_0=2};material=0})});materials=@(@{name='CapsuleMaterial';pbrMetallicRoughness=@{baseColorFactor=@(0.8,0.8,0.8,1.0);metallicFactor=0.0;roughnessFactor=0.8};doubleSided=$true});accessors=@(@{bufferView=0;componentType=5126;count=$vc;type='VEC3';min=@(-0.5,-0.5,-0.5);max=@(0.5,0.5,0.5)},@{bufferView=1;componentType=5126;count=$vc;type='VEC3'},@{bufferView=2;componentType=5126;count=$vc;type='VEC2'});bufferViews=$views.ToArray();buffers=@(@{byteLength=[int]$bin.Length})}

$json=[Text.Encoding]::UTF8.GetBytes(($gltf|ConvertTo-Json -Depth 20 -Compress));while(($json.Length%4)-ne 0){$json+=0x20};$binary=$bin.ToArray();$total=12+8+$json.Length+8+$binary.Length;$out=[IO.MemoryStream]::new();$w=[IO.BinaryWriter]::new($out);$w.Write([uint32]0x46546C67);$w.Write([uint32]2);$w.Write([uint32]$total);$w.Write([uint32]$json.Length);$w.Write([uint32]0x4E4F534A);$out.Write([byte[]]$json,0,$json.Length);$w.Write([uint32]$binary.Length);$w.Write([uint32]0x004E4942);$out.Write([byte[]]$binary,0,$binary.Length);[IO.File]::WriteAllBytes((Join-Path $OutputRoot 'capsule.glb'),$out.ToArray());Write-Output "Created capsule GLB $($out.Length) bytes"