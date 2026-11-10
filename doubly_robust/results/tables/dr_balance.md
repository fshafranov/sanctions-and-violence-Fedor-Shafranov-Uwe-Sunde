# Balance: standardised mean differences (treated - controls), trimmed sample

Rule of thumb: |SMD| < 0.1 balanced. y_l3, y_l4 are not in the propensity model (placebo).

|sample             |timing       |variable |in_propensity | unweighted| ate_weighted| att_weighted|
|:------------------|:------------|:--------|:-------------|----------:|------------:|------------:|
|All state-years    |shock second |y_l1     |TRUE          |      0.405|        0.129|       -0.056|
|All state-years    |shock second |y_l2     |TRUE          |      0.391|        0.096|       -0.054|
|All state-years    |shock second |D_l1     |TRUE          |      0.417|        0.014|       -0.032|
|All state-years    |shock second |D_l2     |TRUE          |      0.319|        0.045|       -0.021|
|All state-years    |shock second |y        |TRUE          |      0.460|        0.108|       -0.072|
|All state-years    |shock second |y_l3     |FALSE         |      0.372|        0.091|       -0.014|
|All state-years    |shock second |y_l4     |FALSE         |      0.310|        0.062|       -0.075|
|All state-years    |shock first  |y_l1     |TRUE          |      0.401|        0.073|       -0.056|
|All state-years    |shock first  |y_l2     |TRUE          |      0.390|        0.076|       -0.056|
|All state-years    |shock first  |D_l1     |TRUE          |      0.417|        0.008|       -0.036|
|All state-years    |shock first  |D_l2     |TRUE          |      0.319|        0.047|       -0.028|
|All state-years    |shock first  |y_l3     |FALSE         |      0.370|        0.079|        0.019|
|All state-years    |shock first  |y_l4     |FALSE         |      0.308|        0.054|       -0.044|
|In conflict in t-1 |shock second |y_l1     |TRUE          |      0.059|        0.041|       -0.008|
|In conflict in t-1 |shock second |y_l2     |TRUE          |      0.084|        0.015|       -0.004|
|In conflict in t-1 |shock second |D_l1     |TRUE          |      0.271|        0.052|       -0.020|
|In conflict in t-1 |shock second |D_l2     |TRUE          |      0.070|       -0.031|        0.007|
|In conflict in t-1 |shock second |y        |TRUE          |      0.119|       -0.007|       -0.007|
|In conflict in t-1 |shock second |y_l3     |FALSE         |      0.100|        0.013|        0.024|
|In conflict in t-1 |shock second |y_l4     |FALSE         |      0.032|       -0.045|       -0.033|
|In conflict in t-1 |shock first  |y_l1     |TRUE          |      0.059|        0.030|       -0.009|
|In conflict in t-1 |shock first  |y_l2     |TRUE          |      0.084|        0.007|       -0.005|
|In conflict in t-1 |shock first  |D_l1     |TRUE          |      0.271|        0.055|       -0.020|
|In conflict in t-1 |shock first  |D_l2     |TRUE          |      0.070|       -0.025|        0.006|
|In conflict in t-1 |shock first  |y_l3     |FALSE         |      0.100|        0.016|        0.030|
|In conflict in t-1 |shock first  |y_l4     |FALSE         |      0.032|       -0.039|       -0.028|
