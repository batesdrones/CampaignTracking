----creating the daily ids for each campaign, IDs are mapped to MSQs---
create or replace table commons.2020_stateleg_dvc_ids as--- own table---
SELECT r.committee_name, extract(date from datetime_canvassed) date, 
(case when contact_type_id = '1' or contact_type_id = '142' then 'Phone'
when contact_type_id = '2' then 'Walk'
when contact_type_id = '37' then 'SMS Text'
when contact_type_id = '145' then 'Relational Canvass'
when contact_type_id = '81' then 'Paid Call'
else null end) contact_type,
count(distinct contacts_contact_id) as responses,
sum (case when survey_response_id = ' '  then 1 else 0 end) as StrongD, ---insert own survey_response_id here for the campaigns survey question---/---
sum (case when survey_response_id = ''  then 1 else 0 end) as LeanD,
sum (case when survey_response_id = '' then 1 else 0 end) as Undecided,
sum (case when survey_response_id = ''  then 1 else 0 end) as LeanGOP,
sum (case when survey_response_id = '' then 1 else 0 end) as StrongGOP
FROM `demskysp.vansync_derived.responses_myv` r
---join `demskysp.commons.ky_active_stateleg` a ---do not need as its only one campaign --/---
----on r.committee_id = a.committee_id 
where (survey_question_id = '') ---insert own 
group by 1,2,3
order by 1;

----aggregating contact attempts to each week, syncing to ISO_week ----
create or replace table demskysp.commons.2020_stateleg_dvc_isoweek as --- own table---
select extract(isoweek from date) week_iso, committee_name, contact_Type, sum(responses) total_responses,sum(strongd) total_strong_d,sum(leand) total_lean_d,sum(undecided) total_undecided,sum(leangop) total_lean_gop,sum(stronggop) total_strong_gop
from demskysp.commons.2020_stateleg_dvc_ids --- own table---
group by 1,2,3;
---/---

----creating the total attempts for the candidates, aggregated at weekly level----/----
create temp table committee_attempts as
select l.committee_id, l.committee_name, extract (year from date_canvassed) year,
extract(isoweek from date_canvassed) week, contact_type_name, count(contacts_contact_id) att
from `vansync_derived.contacts_myv` v
join `commons.ky_active_stateleg` l ---do not need---
on v.committee_id = l.committee_id 
where extract (year from date_canvassed) = 2020 ---update to 2021----
and contact_type_id in ('37','1','2','145')
group by 1,2,3,4,5;

----syncing total attempts from above with countdown to eday----
create temp table committee_attempts_simplify as
select eday_week, week_iso, a.committee_name, contact_TYPE_NAME, att
from committee_attempts a
left join commons.2020_eday_countdown e
on a.week = e.week_iso
group by 1,2,3,4,5;


----creates the weekly report table, calculating each contact type/week pairing as its own table with countdown to eday week--
create or replace table commons.2020_stateleg_weeklyreport as
select a.*, i.* except (committee_name, week_iso)
from committee_attempts_simplify a
left join commons.2020_stateleg_dvc_isoweek i
on a.committee_name = i.committee_name
and i.contact_type = a.contact_type_name
and i.week_iso = a.week_iso;
--/---



-----dvc ids and dnc support score avg---

create temp table stateleg2020
as
SELECT distinct sc.person_id, a.committee_name,
master_survey_response_id response,
dnc_2020_dem_party_support_v1 dnc_support,
EXTRACT (isoweek from datetime_canvassed) week,
eday_week
FROM `demskysp.vansync_derived.responses_myv` myv
join `demskysp.commons.ky_dnc2020_scoresv1` sc ----join on scores_2020 table if available
on myv.person_id = sc.person_id
join `demskysp.commons.ky_active_stateleg` a ----do not need----
on myv.committee_id = a.committee_id 
join `demskysp.commons.2020_eday_countdown` ---need to insert own countdown sheet-
on EXTRACT (isoweek from datetime_canvassed) = week_iso
where  (master_survey_question_id = '4474' or master_survey_question_id = '4475')
and contact_type_id in ('1','2', '37','145');

create temp table  stateleg2020ids
as
select 
distinct person_id,
committee_name,
dnc_support,
(case when (response in('21820','21821','21827','21828')) then 'democrat'
when (response in ('21829','21822')) then 'undecided'
when (response in('21823','21824','21830','21831')) then 'gop'
else 'other-notvoting' end) candidate_id,
week, 
eday_week
from stateleg2020
order by week;

create temp table dem_analysis as
(SELECT  eday_week, committee_name,
count(case when candidate_id = 'democrat' then 1 else null end) democrat_id,
avg((dnc_support*100)) avg_democrat_support
FROM `stateleg2020ids`
where candidate_id = 'democrat'
group by eday_week, committee_name);

create temp table gop_analysis as 
(SELECT eday_week, committee_name,
count(case when candidate_id = 'gop' then 1 else null end) gop_id,
avg((dnc_support*100)) avg_gop_support
FROM `stateleg2020ids`
where candidate_id = 'gop'
group by eday_week, committee_name);

create temp table undecided_analysis as 
(SELECT eday_week, committee_name,
count(case when candidate_id = 'undecided' then 1 else null end) undecided_id,
avg((dnc_support*100)) avg_undecided_support
FROM `stateleg2020ids`
where candidate_id = 'undecided'
group by eday_week, committee_name);

create temp table id_avg as 
(select eday_week , committee_name,
(avg((dnc_support*100))) id_avg
from `stateleg2020ids`
group by eday_week, committee_name);

create or replace table demskysp.sbx_howertonj.2020_stateleg_dvc_scores
as
select distinct d.eday_week , d.committee_name, ifnull(democrat_id,0) democrat_id, ifnull(avg_democrat_support,0) avg_democrat_support, ifnull(gop_id,0) gop_id, ifnull(avg_gop_support,0) avg_gop_support, ifnull(undecided_id,0) undecided_id, ifnull(avg_undecided_support,0) avg_undecided_support, id_avg
from dem_analysis d
left join gop_analysis g
on d.eday_week = g.eday_week and d.committee_name = g.committee_name
left join
undecided_analysis u 
on d.eday_week = u.eday_week and d.committee_name = u.committee_name
left join id_avg i
on d.eday_week = i.eday_week and d.committee_name = i.committee_name
;

--/---


----Weekly PTG---


create or replace table demskysp.commons.2020_stateleg_ptg
as

(SELECT r.eday_week, r.committee_name, contact_type_name,
(case when contact_type_name = 'Phone' then (att/phone_goal) else 0 end) ptg,
att, phone_goal as goal
FROM `demskysp.commons.2020_stateleg_weeklyreport` r
join `demskysp.sbx_howertonj.2020_stateleg_weeklygoals` g
on (r.committee_name = g.campaign
and cast(r.eday_week as string) =  WeeksToEday)
where r.contact_TYPE_NAME = 'Phone'
order by 1,2)

union all

(SELECT r.eday_week, r.committee_name, contact_type_name,
(case when contact_type_name = 'Walk' then (att/door_goal) else 0 end) ptg,
att, door_goal as goal
FROM `demskysp.commons.2020_stateleg_weeklyreport` r
join `demskysp.sbx_howertonj.2020_stateleg_weeklygoals` g
on (r.committee_name = g.campaign
and cast(r.eday_week as string) =  WeeksToEday)
where r.contact_TYPE_NAME = 'Walk'
order by 1,2)

union all 

(SELECT r.eday_week, r.committee_name, contact_type_name,
(case when contact_type_name = 'SMS Text' then (att/p2p_text_goal) else 0 end) ptg,
att, p2p_text_goal as goal
FROM `demskysp.commons.2020_stateleg_weeklyreport` r
join `demskysp.sbx_howertonj.2020_stateleg_weeklygoals` g
on (r.committee_name = g.campaign
and cast(r.eday_week as string) =  WeeksToEday)
where r.contact_TYPE_NAME = 'SMS Text'
order by 1,2)


union all

(with goals as
(SELECT WeeksToEday, Campaign, sum( Door_Goal +  Phone_Goal + P2P_Text_Goal) as totalweeklygoal
FROM `demskysp.sbx_howertonj.2020_stateleg_weeklygoals` 
group by 1,2), 
 att as
(select eday_week as weekstoeday, committee_name as campaign, sum(att) as atts
from `commons.2020_stateleg_weeklyreport` 
group by 1,2)

select a.weekstoeday, g.campaign, "WEEKLY TOTAL" as contact_type_name, (atts/totalweeklygoal) as ptg, atts, totalweeklygoal
from att a
join goals g
on (a.campaign = g.campaign
and cast(a.weekstoeday as string) =  g.WeeksToEday)
group by 1,2,3,5,6)

---/----
