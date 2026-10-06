function New-AdaptiveSamplingState {
 @{thermal=[datetime]::MinValue;family=[datetime]::MinValue;background=[datetime]::MinValue}
}
function Get-AdaptiveSamplePlan {
 param([hashtable]$State,[datetime]$At=(Get-Date),[int]$SlowSeconds=3)
 $plan=@{}
 foreach($key in @('thermal','family','background')){$plan[$key]=($At-$State[$key]).TotalSeconds -ge $SlowSeconds}
 $plan
}
