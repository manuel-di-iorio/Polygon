param([string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\datafiles\demo'))
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.IO.Compression;
public static class DemoTerrainPng {
  static uint[] table=MakeTable();
  static uint[] MakeTable(){var t=new uint[256];for(uint n=0;n<256;n++){uint c=n;for(int k=0;k<8;k++)c=(c&1)!=0?0xedb88320u^(c>>1):c>>1;t[n]=c;}return t;}
  static uint Crc(byte[] b){uint c=0xffffffff;for(int i=0;i<b.Length;i++)c=table[(c^b[i])&255]^(c>>8);return c^0xffffffff;}
  static void Chunk(Stream s,string type,byte[] data){var name=System.Text.Encoding.ASCII.GetBytes(type);var len=BitConverter.GetBytes(System.Net.IPAddress.HostToNetworkOrder(data.Length));s.Write(len,0,4);s.Write(name,0,4);s.Write(data,0,data.Length);var all=new byte[4+data.Length];Buffer.BlockCopy(name,0,all,0,4);Buffer.BlockCopy(data,0,all,4,data.Length);var crc=BitConverter.GetBytes(System.Net.IPAddress.HostToNetworkOrder(unchecked((int)Crc(all))));s.Write(crc,0,4);}
  static double Hash(int x,int y){unchecked{uint n=(uint)(x*374761393+y*668265263);n=(n^(n>>13))*1274126177u;n^=n>>16;return (n&0x00ffffff)/8388607.5-1.0;}}
  static double Noise(int x,int y,int size,int cells){double fx=(double)x*cells/size,fy=(double)y*cells/size;int ix=(int)Math.Floor(fx),iy=(int)Math.Floor(fy);double tx=fx-ix,ty=fy-iy;tx=tx*tx*(3-2*tx);ty=ty*ty*(3-2*ty);int ax=(ix%cells+cells)%cells,bx=(ax+1)%cells,ay=(iy%cells+cells)%cells,by=(ay+1)%cells;double a=Hash(ax,ay),b=Hash(bx,ay),c=Hash(ax,by),d=Hash(bx,by);return (a+(b-a)*tx)+((c+(d-c)*tx)-(a+(b-a)*tx))*ty;}
  public static byte[] Build(int size){var raw=new byte[size*(size*4+1)];for(int y=0;y<size;y++){int row=y*(size*4+1);raw[row]=0;for(int x=0;x<size;x++){double broad=Noise(x,y,size,8),mid=Noise(x,y,size,32),fine=Noise(x,y,size,128),grain=Noise(x,y,size,256);double soil=Math.Max(0,Math.Min(1,(broad-0.24)*2.7));double moss=Math.Max(0,Math.Min(1,(mid+0.35)*0.8));double n=.5+broad*.19+mid*.11+fine*.055+grain*.025;int p=row+1+x*4;double red=45+n*35+soil*79+moss*4;double green=78+n*72-soil*44+moss*14;double blue=38+n*31-soil*25+moss*10;raw[p]=(byte)Math.Max(0,Math.Min(255,red));raw[p+1]=(byte)Math.Max(0,Math.Min(255,green));raw[p+2]=(byte)Math.Max(0,Math.Min(255,blue));raw[p+3]=255;}}
    byte[] compressed;using(var m=new MemoryStream()){using(var z=new ZLibStream(m,CompressionLevel.Optimal,true))z.Write(raw,0,raw.Length);compressed=m.ToArray();}
    using(var png=new MemoryStream()){png.Write(new byte[]{137,80,78,71,13,10,26,10},0,8);var ihdr=new byte[13];Buffer.BlockCopy(BitConverter.GetBytes(System.Net.IPAddress.HostToNetworkOrder(size)),0,ihdr,0,4);Buffer.BlockCopy(BitConverter.GetBytes(System.Net.IPAddress.HostToNetworkOrder(size)),0,ihdr,4,4);ihdr[8]=8;ihdr[9]=6;Chunk(png,"IHDR",ihdr);Chunk(png,"IDAT",compressed);Chunk(png,"IEND",new byte[0]);return png.ToArray();}}
}
"@
function To-FloatBytes([single[]]$Values) { $m=[IO.MemoryStream]::new(); foreach($v in $Values){$b=[BitConverter]::GetBytes([single]$v);$m.Write($b,0,$b.Length)}; return ,$m.ToArray() }
function To-UShortBytes([uint16[]]$Values) { $m=[IO.MemoryStream]::new(); foreach($v in $Values){$b=[BitConverter]::GetBytes([uint16]$v);$m.Write($b,0,$b.Length)}; return ,$m.ToArray() }
$png=[DemoTerrainPng]::Build(512)
[IO.File]::WriteAllBytes((Join-Path $OutputRoot 'terrain_grass.png'),$png)
$radius=15.0;$segments=64
$positions=[Collections.Generic.List[single]]::new();$normals=[Collections.Generic.List[single]]::new();$uvs=[Collections.Generic.List[single]]::new();$indices=[Collections.Generic.List[uint16]]::new()
$positions.AddRange([single[]]@(0,0,0));$normals.AddRange([single[]]@(0,1,0));$uvs.AddRange([single[]]@(8,8))
for($i=0;$i -lt $segments;$i++){ $a=2.0*[Math]::PI*$i/$segments;$x=[Math]::Cos($a);$z=[Math]::Sin($a);$positions.Add([single]($radius*$x));$positions.Add([single]0);$positions.Add([single]($radius*$z));$normals.AddRange([single[]]@(0,1,0));$uvs.Add([single](8+8*$x));$uvs.Add([single](8+8*$z)) }
for($i=0;$i -lt $segments;$i++){ $cur=[uint16](1+$i);$next=[uint16](1+(($i+1)%$segments));$indices.Add([uint16]0);$indices.Add($next);$indices.Add($cur) }
$bin=[IO.MemoryStream]::new()
function Add-View([byte[]]$Bytes,[Nullable[int]]$Target=$null) { while(($bin.Position%4)-ne 0){$bin.WriteByte(0)}; $offset=[int]$bin.Position; $bin.Write($Bytes,0,$Bytes.Length); $v=@{buffer=0;byteOffset=$offset;byteLength=$Bytes.Length};if($Target.HasValue){$v.target=$Target.Value};return $v }
$views=[Collections.Generic.List[object]]::new()
$views.Add((Add-View (To-FloatBytes $positions.ToArray()) 34962));$views.Add((Add-View (To-FloatBytes $normals.ToArray()) 34962));$views.Add((Add-View (To-FloatBytes $uvs.ToArray()) 34962));$views.Add((Add-View (To-UShortBytes $indices.ToArray()) 34963));$imageViewIndex=$views.Count;$views.Add((Add-View $png));while(($bin.Position%4)-ne 0){$bin.WriteByte(0)}
$gltf=@{asset=@{version='2.0';generator='Polygon demo circular terrain generator'};scene=0;scenes=@(@{nodes=@(0)});nodes=@(@{mesh=0;name='DemoGrassTerrain'});meshes=@(@{name='CircularMeadowMesh';primitives=@(@{attributes=@{POSITION=0;NORMAL=1;TEXCOORD_0=2};indices=3;material=0;mode=4})});materials=@(@{name='Irregular Meadow';pbrMetallicRoughness=@{baseColorTexture=@{index=0};baseColorFactor=@(0.92,0.97,0.88,1.0);metallicFactor=0.0;roughnessFactor=1.0};doubleSided=$true});textures=@(@{sampler=0;source=0});samplers=@(@{magFilter=9729;minFilter=9987;wrapS=10497;wrapT=10497});images=@(@{bufferView=$imageViewIndex;mimeType='image/png';name='Irregular Grass and Soil'});accessors=@(@{bufferView=0;componentType=5126;count=65;type='VEC3';min=@(-15,0,-15);max=@(15,0,15)},@{bufferView=1;componentType=5126;count=65;type='VEC3'},@{bufferView=2;componentType=5126;count=65;type='VEC2';min=@(0,0);max=@(16,16)},@{bufferView=3;componentType=5123;count=192;type='SCALAR';min=@(0);max=@(64)});bufferViews=$views.ToArray();buffers=@(@{byteLength=[int]$bin.Length})}
$json=[Text.Encoding]::UTF8.GetBytes(($gltf|ConvertTo-Json -Depth 20 -Compress));while(($json.Length%4)-ne 0){$json+=0x20};$binary=$bin.ToArray();$total=12+8+$json.Length+8+$binary.Length;$out=[IO.MemoryStream]::new();$w=[IO.BinaryWriter]::new($out);$w.Write([uint32]0x46546C67);$w.Write([uint32]2);$w.Write([uint32]$total);$w.Write([uint32]$json.Length);$w.Write([uint32]0x4E4F534A);$out.Write([byte[]]$json,0,$json.Length);$w.Write([uint32]$binary.Length);$w.Write([uint32]0x004E4942);$out.Write([byte[]]$binary,0,$binary.Length);[IO.File]::WriteAllBytes((Join-Path $OutputRoot 'terrain.glb'),$out.ToArray());Write-Output "Created circular terrain (diameter $($radius*2)m), GLB $($out.Length) bytes"
