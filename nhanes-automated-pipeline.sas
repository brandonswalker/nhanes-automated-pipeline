
/* =========================================================================
Configurable Multi-Year & Multi-Module NHANES Pipeline
Instructions: Add or remove module names or years in the lists below.

YEAR CODES
1999-2000: 1999  | 2001-2002: 2001  | 2003-2004: 2003 | 2005-2006: 2005  |  2007-2008: 2007 
2009-2010: 2009  | 2011-2012: 2011  | 2013-2014: 2013 | 2015-2016: 2015  |  2017-2018: 2017 
2021-2023: 2021
Other years not available at the time this code was written 
  
MODULE CODES (Other modules in NHANES not listed below may have different names by survey year)  
DEMO - Demographic Variables & Survey Design (Age, Gender, Race/Ethnicity, Education, Income, Full Sample 2-Year Weights, PSU, Strata)
BMX - Body Measures (Height, Weight, BMI, Waist Circumference)
BPX - Blood Pressure (Oscillometric Systolic/Diastolic Readings & Pulse Rate)
ALQ - Alcohol Use (Frequency, Quantity, and Patterns of Alcohol Consumption)
BPQ - Blood Pressure & Cholesterol (Personal Diagnosis & Prescription Medication History)
CDQ - Cardiovascular Disease (Chest Pain, Angina, and Heart Attack History)
DIQ - Diabetes (Doctor-Diagnosed Diabetes, Age at Diagnosis, Insulin & Oral Medication Use)
DPQ - Depression Screener (Patient Health Questionnaire / PHQ-9 Assessment)
DUQ - Drug Use (Illicit and Prescription Drug Consumption Patterns)
FSQ - Food Security (Household and Individual Food Insecurity Scales)
HIQ - Health Insurance (Coverage Status, Types of Public and Private Insurance Plans)
HSQ - General Health Status (Self-Reported Health Condition and Recent Hospitalizations)
HUQ - Hospital Utilization & Care Access (Routine Healthcare Provider & Hospital Visits)
MCQ - Medical Conditions (Self-Reported History of Asthma, Arthritis, Cancer, Stroke, etc.)
OCQ - Occupation (Employment Status, Industry, and Work Hours)
PAQ - Physical Activity (Work, Transportation, Leisure-Time Exercise, and Sedentary Habits)
RDQ - Respiratory Health (Cough, Phlegm, Wheezing, and Shortness of Breath Symptoms)
SLQ - Sleep Disorders (Sleep Duration, Snoring, and Sleep Apnea Symptoms)
SMQ - Smoking / Tobacco Use (Cigarette, Cigar, Pipe, and Tobacco Product History)
SXQ - Sexual Behavior (Lifetime and Recent Sexual History)
WHQ - Weight History (Self-Reported Historical Weight, Maximum Weight, and Weight Loss Intentions)

NOTE: The naming of BPX changed to BPXO in 2021 and is not currently accounted for in the code and 
will cause an error if included in 2021
========================================================================= */

/* 1. CONFIGURATION SECTION (Modify your datasets, years, and save path here) */
%let modules   = DEMO BPX BMX ALQ BPQ HIQ SMQ;
%let years     = 1999 2001 2003 2005 2007 2009 2011 2013 2015 2017;
/*Change save path to appriopriate location */
%let save_path = /home/u1856730/NHANES; 


/* 2. AUTOMATED PROCESSING MACRO */
%macro process_nhanes_pipeline;
    
    /* Loop through each year in the space-delimited list */
    %local i yr letter suff;
    %let i = 1;
    %do %while (%scan(&years., &i, %str( )) ne );
        %let yr = %scan(&years., &i, %str( ));
        
        /* Compute letter suffix: 
           1999 -> No letter suffix (suff is empty, file is DEMO.xpt)
           2001+ -> _B, _C, _D, etc. (suff is _B, _C, etc.) */
        %if &yr. = 1999 %then %do;
            %let letter = ;
            %let suff   = ;
        %end;
        %else %do;
            %let letter = %sysfunc(byte(%eval(65 + (&yr - 1999)/2)));
            %let suff   = _&letter.;
        %end;
        
        /* A. Download and import each module for this cycle */
        %local j mod;
        %let j = 1;
        %do %while (%scan(&modules., &j, %str( )) ne );
            %let mod = %scan(&modules., &j, %str( ));
            
            filename f_temp temp;
            proc http 
                method="GET" 
                url="https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/&yr./DataFiles/&mod.&suff..xpt" 
                out=f_temp; 
            run;
            
            libname x_temp xport "%sysfunc(pathname(f_temp))";
            proc copy in=x_temp out=work; run;
            libname x_temp clear;
            filename f_temp clear;
            
            %let j = %eval(&j + 1);
        %end;

        /* B. Sort all modules by SEQN */
        %let j = 1;
        %do %while (%scan(&modules., &j, %str( )) ne );
            %let mod = %scan(&modules., &j, %str( ));
            proc sort data=work.&mod.&suff.; by seqn; run;
            %let j = %eval(&j + 1);
        %end;

        /* C. Dynamically merge all modules for this specific year */
        data work.nhanes_&yr.;
            merge 
            %let j = 1;
            %do %while (%scan(&modules., &j, %str( )) ne );
                %let mod = %scan(&modules., &j, %str( ));
                %if &j = 1 %then work.&mod.&suff. (in=d);
                %else work.&mod.&suff.;
                %let j = %eval(&j + 1);
            %end;
            ;
            by seqn;
            if d; 
        run;

        /* D. Clean up individual raw module files for this cycle */
        proc datasets lib=work nolist;
            delete 
            %let j = 1;
            %do %while (%scan(&modules., &j, %str( )) ne );
                %let mod = %scan(&modules., &j, %str( ));
                &mod.&suff.
                %let j = %eval(&j + 1);
            %end;
            ;
        run;
        quit;

        %let i = %eval(&i + 1);
    %end;


    /* E. Dynamically stack all 10 yearly merged files into one master dataset */
    data work.nhanes_all;
        set 
        %let i = 1;
        %do %while (%scan(&years., &i, %str( )) ne );
            %let yr = %scan(&years., &i, %str( ));
            work.nhanes_&yr.
            %let i = %eval(&i + 1);
        %end;
        ;
    run;

%mend;


/* 3. EXECUTE PIPELINE */
%process_nhanes_pipeline;


/* 4. SAVE PERMANENTLY TO YOUR NHANES DIRECTORY */
libname myfolder "&save_path.";

data myfolder.nhanes_all;
    set work.nhanes_all;
run;

/* Clean up intermediate files in WORK */
proc datasets lib=work nolist;
    save nhanes_all;
run;
quit;