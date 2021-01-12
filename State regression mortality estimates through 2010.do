	capture clear all
	set more off, perm
	capture log close

	cd "..."
	
	global input ".\Input"
	global temp ".\Temp"
	global output ".\Output"
	global data "..."
	global chart_sch  "..."

	global c_blue `""93 165 218""'
	global c_red `""241 88 84""'
	global c_green `""96 189 104""'
	global c_orange `""250 164 58""'
	global c_purple `""178 118 178""'
	global c_brown `""153 102 51""'
	global c_lightblue `""172 209 236""'
	global c_lightred `""247 164 161""'
	global c_black `""0 0 0""'
	global c_grey `""128 128 128""'
	graph set window  fontface "Calibri"
	global size_yestitle = "ysize(8.5) xsize(11)"
	global size_notitle = "ysize(7.5) xsize(11)"

	adopath + "$chart_sch"
	set scheme cl_chart, perm
	
	foreach rate in "any_rate4" "licit_rate2" "hybrid_rate2" {
	
	if "`rate'" == "any_rate4" {
		local pre_1 1993
		local pre_2 1995
		local post_1 2009
		local post_2 2010
		
		local model_1 = "model 1a"
		local model_2 = "model 1aa"
	}
	
	else if "`rate'" == "licit_rate2" {
		local pre_1 1999
		local pre_2 2000
		local post_1 2009
		local post_2 2010
		
		local model_1 = "model 2a"
		local model_2 = "model 2aa"
	}
	
	else if "`rate'" == "hybrid_rate2" {
		local pre_1 1999
		local pre_2 2000
		local post_1 2009
		local post_2 2010
		
		local model_1 = "model 3a"
		local model_2 = "model 3aa"
	}
	
	// Create shipping variable
	use "$data\arcos_state_imputed", clear
	merge 1:1 fips year using "$data\combined_demo_state", keep(match) nogen keepusing(pop_adult)
	drop if fip=="11"
	gen ship_pc_pd = mme_total/pop_adult/365
	gen ship_97t10 = ship_pc_pd
	replace ship_97t10 = . if year>2010 | year<1997
	gen ship_97 = ship_pc_pd
	replace ship_97 = . if year!=1997
	collapse (mean) ship_97t10 ship_97, by(fips)
	tempfile ship
	save `ship'
	
	// Import state mortality data
	use "$data/state_mort_8318_rev1204", clear
	rename state_code fips
	merge 1:1 fips year using "$data\combined_demo_state", keep(match) nogen
	
	// Create variables for ages <30 and 30-64
	gen age12_pct = age1_pct + age2_pct
	gen age34_pct = age3_pct + age4_pct
	
	// Create pre and post periods
	gen period = "pre" if year<=`pre_2' & year>=`pre_1'
	replace period = "post" if year<=`post_2' & year>=`post_1'
	drop if mi(period)
	
	// Calculate percentage changes between pre and post periods
	local temp_controls = "med_house prime_emp_to_pop_cps race1_pct less_high"
	gsort +fips +period
	by fips period: egen base_mort = wtmean(`rate'), weight(pop_adult)
	collapse base_mort (mean) pop_tot `temp_controls', by(period fips)
	replace pop_tot = pop_tot/1000
	reshape wide base_mort pop_tot `temp_controls', i(fips) j(period) string
	
	gen pop_tot_pct_chg = (pop_totpost-pop_totpre) / pop_totpre
	drop pop_totpost pop_totpre
	
	local base_chg = ""
	foreach var in `temp_controls' {
		local base_chg = "`base_chg' `var'_chg"
		gen `var'_chg = `var'post-`var'pre
		rename `var'pre `var'
		drop `var'post
	}
	gen `rate'_chg = base_mortpost-base_mortpre
	
	// Create "East" variable
	gen region = 1 if inlist(fips,"09","23","25","33","44","50")
	replace region = 1 if inlist(fips,"34","36","42")
	replace region = 2 if inlist(fips,"17","18","26","39","55")
	replace region = 2 if inlist(fips,"19","20","27","29","31","38","46")
	replace region = 3 if inlist(fips,"10","11","12","13","24","37","45","51","54")
	replace region = 3 if inlist(fips,"01","21","28","47")
	replace region = 3 if inlist(fips,"05","22","40","48")
	replace region = 4 if inlist(fips,"04","08","16","30","32","35","49","56")
	replace region = 4 if inlist(fips,"02","06","15","41","53")
	
	gen division = 1 if inlist(fips,"09","23","25","33","44","50")
	replace division = 2 if inlist(fips,"34","36","42")
	replace division = 3 if inlist(fips,"17","18","26","39","55")
	replace division = 4 if inlist(fips,"19","20","27","29","31","38","46")
	replace division = 5 if inlist(fips,"10","11","12","13","24","37","45","51","54")
	replace division = 6 if inlist(fips,"01","21","28","47")
	replace division = 7 if inlist(fips,"05","22","40","48")
	replace division = 8 if inlist(fips,"04","08","16","30","32","35","49","56")
	replace division = 9 if inlist(fips,"02","06","15","41","53")
	
	gen east = 1 if inlist(division,1,2,3,5,6)
	replace east = 0 if mi(east)
	drop if fip=="11"

	// Regression
	merge 1:1 fips using `ship', nogen
	local base_controls = "base_mortpre med_house_chg prime_emp_to_pop_cps_chg race1_pct_chg less_high_chg pop_tot_pct_chg"
	summarize ship_97t10 `base_controls'
	reg `rate'_chg ship_97t10 `base_controls', robust
	adjust ship_97t10=0 `base_controls', gen(yhat)
	gen ship_coef = _b["ship_97t10"]
	
	outreg2 using "$temp/`model_1'.xls", replace excel title("Regression Results") ctitle("Estimated Coefficients") stats(coef se tstat pval) symbol(**, *, ~) nonote addnote(P-value in parentheses, "** p<0.01, * p<0.05, ~ p<0.1") dec(4) drop(o.*) addstat(Adjusted R-squared, e(r2_a))
	
	// Actual and But-For Mortality
	gen impact = ship_coef * (ship_97t10 - ship_97)
	rename base_mortpost actual
	gen but_for = actual - impact
	collapse (mean) actual impact but_for
	gen percent_elevation = (actual / but_for) - 1
	drop impact	
	
	label var actual "Actual Mortality Rate"
	label var but_for "Implied But-For Mortality Rate"
	label var percent_elevation "Percent Elevation"		
	
	export excel using "$output/Regressions for Report.xlsx", sheet("`model_2'") sheetreplace first(varl)
	export excel using "$output/State Regressions for Report.xlsx", sheet("`model_2'") sheetreplace first(varl)
	}
	
	// Export
	foreach var in "model 1a" "model 2a" "model 3a" {
		clear
		import delimited "$temp/`var'.txt"
		export excel using "$output/Regressions for Report.xlsx", sheet("`var'") sheetreplace
		export excel using "$output/State Regressions for Report.xlsx", sheet("`var'") sheetreplace
	}
	
