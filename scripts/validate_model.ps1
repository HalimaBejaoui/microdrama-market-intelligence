# Compares every report measure with values calculated independently from the gold CSV files.
# Open microdrama-market-study.pbip in Power BI Desktop and refresh first. Usage: powershell -File validate_model.ps1
$pbi = (Get-AppxPackage -Name Microsoft.MicrosoftPowerBIDesktop).InstallLocation
Add-Type -Path "$pbi\bin\Microsoft.PowerBI.AdomdClient.dll"
$ws = Get-ChildItem "$env:USERPROFILE\Microsoft\Power BI Desktop Store App\AnalysisServicesWorkspaces" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$port = (Get-Content "$($ws.FullName)\Data\msmdsrv.port.txt" -Raw -Encoding Unicode).Trim()
$c = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection "Data Source=localhost:$port"; $c.Open()
function V([string]$expr) { $cmd = $c.CreateCommand(); $cmd.CommandText = "EVALUATE ROW(""v"", $expr)"; $r = $cmd.ExecuteReader(); $null = $r.Read(); $x = $r.GetValue(0); $r.Close(); return $x }
$script:ok = 0; $script:bad = 0
function T([string]$label, [string]$expr, $exp, [double]$tol = 0.005) {
  $v = V $expr
  if ($exp -is [string]) { $pass = ("$v" -eq $exp) }
  elseif ($null -eq $exp) { $pass = ($null -eq $v -or $v -is [DBNull]) }
  elseif ($v -is [DBNull] -or $null -eq $v) { $pass = $false }
  else { $pass = ([math]::Abs([double]$v - [double]$exp) -le ($tol * [math]::Max(1, [math]::Abs([double]$exp)))) }
  if ($pass) { $script:ok++ } else { $script:bad++; "FAIL  $label  got=[$v] expected=[$exp]" }
}
function ByMR([string]$m, [string]$mr) { "CALCULATE([$m], Dim_Region[Marketing Region]=""$mr"")" }
function ByR([string]$m, [string]$r) { "CALCULATE([$m], Dim_Region[Region]=""$r"")" }
function Scen([string]$m, [string]$mr, [string]$ct) { "CALCULATE([$m], Dim_MarketingRegion[Marketing Region]=""$mr"", Dim_ContentType[Content Type]=""$ct"")" }
$NA="North America"; $EU="Europe / Middle East"; $AP="Asia-Pacific"; $LA="Latin America"; $L="Locally Made"; $D="Dubbed"

T "Latest IAP" "[Latest IAP Revenue]" 750; T "Latest DL" "[Latest Downloads]" 850; T "Latest RPD" "[Latest Revenue per Download]" (750/850)
T "IAP YoY" "[IAP Revenue YoY %]" 0.2; T "DL YoY" "[Downloads YoY %]" (850/354-1); T "RPD YoY" "[Revenue per Download YoY %]" (((750/850)-(625/354))/(625/354))
T "All-quarter IAP" "[IAP Revenue]" 4980; T "Q3 25 IAP" "CALCULATE([IAP Revenue],'Date'[Year Quarter]=""2025 Q3"")" 780
foreach ($r in @(@($NA,277.5,25.5,5.28),@($EU,142.5,42.5,1.03),@($AP,165,501.5,0.93),@($LA,60,195.5,0.34))) {
  T "Rev $($r[0])" (ByMR "Region Revenue" $r[0]) $r[1]; T "DL $($r[0])" (ByMR "Region Downloads" $r[0]) $r[2]; T "CPI $($r[0])" (ByMR "Region CPI" $r[0]) $r[3]
  T "RPD $($r[0])" (ByMR "Region Revenue per Download" $r[0]) ($r[1]/$r[2]); T "Mult $($r[0])" (ByMR "Revenue to CPI Multiple" $r[0]) ($r[1]/$r[2]/$r[3])
  T "RevShare $($r[0])" (ByMR "Region Revenue Share" $r[0]) ($r[1]/750); T "DLShare $($r[0])" (ByMR "Region Download Share" $r[0]) ($r[2]/850)
}
T "US YoY" (ByR "Region Revenue YoY %" "United States") (-0.11); T "Europe YoY" (ByR "Region Revenue YoY %" "Europe") 0.88; T "India YoY" (ByR "Region Revenue YoY %" "India") 1.07; T "Others YoY blank" (ByR "Region Revenue YoY %" "Others") $null
T "Top region" "[Top Return Region]" $EU; T "Top multiple" "[Top Return Multiple]" (142.5/42.5/1.03)
T "CPI NA" "CALCULATE([Cost per Install],Dim_MarketingRegion[Marketing Region]=""$NA"")" 5.28
T "Meta" "CALCULATE([Ad Channel Share],Fact_BenchmarkMix[Item]=""Meta"")" 0.65; T "Marketing cost" "CALCULATE([Cost Structure Share],Fact_BenchmarkMix[Item]=""Marketing"")" 0.5; T "AI saving" "[AI Production Saving]" 0.85
T "Local conv" "[Local Payer Conversion]" 0.1; T "Dub conv" "[Dubbed Payer Conversion]" 0.04; T "ROI" "[Local ROI Multiple]" 2.5; T "Local 2026F" "[Local Share 2026F]" 0.4414
T "Completion local" "CALCULATE([Rate Benchmark],Fact_ContentBenchmark[Metric]=""Completion Rate"",Dim_ContentType[Content Type]=""$L"")" 0.525
T "Retention dub" "CALCULATE([Rate Benchmark],Fact_ContentBenchmark[Metric]=""7-Day Retention"",Dim_ContentType[Content Type]=""$D"")" 0.2
T "ARPU local" "CALCULATE([ARPU Benchmark],Dim_ContentType[Content Type]=""$L"")" 32.5
T "Comeback heat/title" "CALCULATE([Heat per Title],Fact_Genre[Genre]=""Comeback"")" (14390/5178); T "Family heat/title" "CALCULATE([Heat per Title],Fact_Genre[Genre]=""Family ethics"")" (5470/1705); T "CEO heat/title" "CALCULATE([Heat per Title],Fact_Genre[Genre]=""CEO"")" (6620/2996)
T "US format mid" "CALCULATE([Format Cost Midpoint],Fact_FormatCost[Format]=""Live-Action (US)"")" 200; T "AI West mid" "CALCULATE([Format Cost Midpoint],Fact_FormatCost[Format]=""AI (West, per hour)"")" 25; T "Latest AI share" "[Latest AI Release Share]" 0.667
foreach ($s in @(@($NA,$D,0.04,15),@($NA,$L,0.10,32.5),@($EU,$D,0.04,15),@($EU,$L,0.10,32.5),@($AP,$D,0.04,15),@($AP,$L,0.10,32.5),@($LA,$D,0.04,15),@($LA,$L,0.10,32.5))) {
  $cpi = @{$NA=5.28;$EU=1.03;$AP=0.93;$LA=0.34}[$s[0]]; $cac = $cpi/$s[2]; $con = $s[3]-$cac
  T "CAC $($s[0]) $($s[1])" (Scen "Cost to Win a Payer" $s[0] $s[1]) $cac; T "Contrib $($s[0]) $($s[1])" (Scen "Contribution per Payer" $s[0] $s[1]) $con
  if ($con -gt 0) { $p=[math]::Ceiling(25000/$con); T "BE $($s[0]) $($s[1])" (Scen "Break-even Payers" $s[0] $s[1]) $p; T "Budget $($s[0]) $($s[1])" (Scen "Marketing Budget to Break Even" $s[0] $s[1]) ($p*$cac) }
  else { T "BE blank $($s[0]) $($s[1])" (Scen "Break-even Payers" $s[0] $s[1]) $null }
}
T "Scenario ARPU +20%" "CALCULATE([Scenario ARPU],'ARPU Adjustment'[ARPU Adjustment]=20,Dim_ContentType[Content Type]=""$L"")" 39
T "Production 150k" "CALCULATE([Selected Production Cost],'Production Cost'[Production Cost]=150000)" 150000
T "RS revenue" "CALCULATE([App Revenue 2025],Dim_App[App]=""ReelShort"")" 332; T "RS per MAU" "CALCULATE([Revenue per MAU],Dim_App[App]=""ReelShort"")" (332/11.133); T "DB per MAU" "CALCULATE([Revenue per MAU],Dim_App[App]=""DramaBox"")" (294.7/31.06)
T "Top 2" "[Top 2 App Share]" (626.7/2057.73); T "Top 10" "[Top 10 App Share]" (1248.3/2057.73); T "US share RS" "CALCULATE([US Revenue Share],Dim_App[App]=""ReelShort"")" (233.5/332)
T "FreeReels ads" "CALCULATE([Ad Share],Dim_App[App]=""FreeReels"")" 0.99; T "RS Q1 26" "CALCULATE([App Revenue Q1 2026],Dim_App[App]=""DramaBox"")" 136; T "RS monthly total" "CALCULATE([App Monthly Revenue],Dim_App[App]=""ReelShort"")" 332
T "MS China 2026" "CALCULATE([Market Size China],'Date'[Year]=2026)" 16.81; T "MS Outside 2024" "CALCULATE([Market Size Outside China],'Date'[Year]=2024)" 1.4; T "2026E" "[Overseas Market 2026E]" 3.6;T "2026E YoY" "[Overseas Market 2026E YoY %]" (3.6/2.7-1)
T "Crazy Maple margin" "CALCULATE([Operator Net Margin],Fact_Operator[Company]=""Crazy Maple Studio"")" (-11.9/794.6); T "COL margin" "CALCULATE([Operator Net Margin],Fact_Operator[Company]=""COL Group"")" (-93.2/230.1); T "Dianzhong margin blank" "CALCULATE([Operator Net Margin],Fact_Operator[Company]=""Dianzhong Technology"")" $null
T "Kunlun cap" "CALCULATE([Operator Market Cap],Fact_Operator[Company]=""Kunlun Tech"")" 6708.3
T "RS monthly" "CALCULATE([ReelShort Price],Fact_Pricing[Plan]=""Monthly"")" 15.99; T "RS weekly" "CALCULATE([Plan Price],Fact_Pricing[Plan]=""Weekly"")" 12.99
T "Free share RS" "CALCULATE([Free Episode Share],Dim_App[App]=""ReelShort"")" (43/241); T "Free share SM" "CALCULATE([Free Episode Share],Dim_App[App]=""ShortMax"")" (28/131)
# six-page public version
T "Free share all" "[Free Episode Share]" (71/372); T "RS monthly KPI" "[ReelShort Monthly Price]" 15.99; T "FreeReels KPI" "[FreeReels Ad Share]" 0.99
T "Overseas rev 2025" "[Overseas Revenue 2025]" 2.05773; T "Overseas rev YoY" "[Overseas Revenue 2025 YoY %]" (2057.73/910.21-1); T "Overseas rev 2023" "CALCULATE([Overseas Revenue],Fact_OverseasYear[Year]=""2023"")" 86.87
T "Overseas DL 2025" "[Overseas Downloads 2025]" 2.148; T "Overseas DL YoY" "[Overseas Downloads 2025 YoY %]" (21.48/5.34-1)
T "NA rev share" "[North America Revenue Share]" 0.546; T "NA DL share" "[North America Download Share]" 0.121; T "Asia DL share" "[Asia Download Share]" 0.598; T "Asia rev share" "[Asia Revenue Share]" 0.326
T "NA rev/DL" "[North America Revenue per Download]" (1123/260); T "SA rev/DL" "[South America Revenue per Download]" (63/376); T "Europe rev/DL" "CALCULATE([Continent Revenue per Download],Fact_ContinentPerformance[Continent]=""Europe"")" (142/112)
T "Saudi DramaBox" "CALCULATE([Middle East Revenue Growth],Fact_MenaGrowth[Label]=""DramaBox, Saudi Arabia"")" 10.642
T "RS US revenue" "CALCULATE([App Country Revenue],Fact_AppCountry[App]=""ReelShort"",Fact_AppCountry[Country Group]=""United States"")" 233.5; T "RS country total" "CALCULATE([App Country Revenue],Fact_AppCountry[App]=""ReelShort"")" 331.9
T "Top per MAU app" "[Top Revenue per MAU App]" "ReelShort"; T "Top per MAU" "[Top Revenue per MAU]" (332/11.133); T "Fastest app" "[Fastest Growing App]" "My Drama"; T "Fastest growth" "[Fastest App Growth]" 0.51
T "China 2025" "[China Market 2025]" (1000/72); T "China YoY" "[China Market 2025 YoY %]" (1000/505-1); T "China free share" "[Free Share of China Market 2025]" 0.533
T "China free 2026E" "CALCULATE([China Free Market],Fact_ChinaMarket[Year]=""2026E"")" (573/72); T "China paid 2025" "CALCULATE([China Paid Market],Fact_ChinaMarket[Year]=""2025"")" (467/72)
T "Box office" "CALCULATE([China Comparison],Fact_ChinaComparison[Item]=""Film box office"")" (518.32/72); T "China viewers" "[China Viewers]" 696
T "Hongguo Oct" "CALCULATE([Hongguo MAU],Fact_HongguoMAU[Month]=""2025-10"")" 245; T "Under 1M" "[Titles Under 1M]" 0.563; T "Under 5M" "CALCULATE([Title Share],Fact_TitleDistribution[Band]=""Under 5M"")" 0.893
T "Age 30-39" "CALCULATE([China Viewer Share],Fact_ChinaAudience[Age Group]=""30 to 39"")" 0.39
$errs = $c.CreateCommand(); $errs.CommandText = 'EVALUATE FILTER(SELECTCOLUMNS(INFO.MEASURES(),"n",[Name],"e",[ErrorMessage]), [e] <> "")'; $r = $errs.ExecuteReader(); $n = 0; while ($r.Read()) { $n++; "MEASURE ERROR  $($r.GetValue(0)): $($r.GetValue(1))" }; $r.Close()
$c.Close()
"checks passed: $script:ok  failed: $script:bad  measures with errors: $n"
