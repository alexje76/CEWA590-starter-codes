% matlab starter code to scrape USGS stream gage data from NWIS API
%
% J. Thomson, Apr 2024
% Updated 2026 - migrated from deprecated NWISWeb to USGS Water Data API
%   Old URL: waterdata.usgs.gov/nwis/measurements (decommissioned 2025)
%   New API: api.waterdata.usgs.gov/ogcapi/v0/collections/field-measurements
%   Requires MATLAB R2017b or later (webread with JSON support)

gageno='12200500'; % Skagit
%gageno='12061500'; % Skykomish

site_id = ['USGS-' gageno];
base_url = 'https://api.waterdata.usgs.gov/ogcapi/v0/collections/field-measurements/items';
options = weboptions('ContentType', 'json', 'Timeout', 60);

disp(['Fetching field measurements for ' site_id]);

%% Fetch discharge (parameter 00060, ft^3/s) and gage height (00065, ft), first 10k

q_resp = webread(base_url, 'monitoring_location_id', site_id, ...
    'parameter_code', '00060', 'f', 'json', 'limit', 10000, options);

h_resp = webread(base_url, 'monitoring_location_id', site_id, ...
    'parameter_code', '00065', 'f', 'json', 'limit', 10000, options);

disp([num2str(numel(q_resp.features)) ' discharge records, ' ...
      num2str(numel(h_resp.features)) ' gage height records']);

%% Extract fields into arrays

n_q = numel(q_resp.features);
q_ids = cell(n_q, 1);
q_times = cell(n_q, 1);
q_vals = NaN(n_q, 1);
for i = 1:n_q
    p = q_resp.features(i).properties;
    q_ids{i} = p.field_visit_id;
    q_times{i} = p.time;
    q_vals(i) = str2double(p.value);
end

n_h = numel(h_resp.features);
h_times = cell(n_h, 1);
h_vals = NaN(n_h, 1);
for i = 1:n_h
    p = h_resp.features(i).properties;
    h_times{i} = p.time;
    h_vals(i) = str2double(p.value);
end

%% Join on time so each row = one field visit

[~, iq, ih] = intersect(q_times, h_times, 'stable');
discharge = q_vals(iq); % ft^3/s
gageheight = h_vals(ih); % ft

% Parse ISO 8601 timestamps (e.g. '1985-09-25T07:00:00+00:00')

time_strs = q_times(iq);
timestamp = NaN(numel(iq), 1);
for i = 1:numel(iq)
    t = char(time_strs{i});
    timestamp(i) = datenum(datetime(t(1:19), 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss'));
end

%% Sort by time (API returns records in arbitrary order)

[timestamp, sort_idx] = sort(timestamp);
discharge = discharge(sort_idx);
gageheight = gageheight(sort_idx);

%% Quality control

gageheight (gageheight > 50 ) = NaN;

%% Save output
save(['MatlabData_gage' gageno '.mat'],'gageheight','discharge','timestamp')

%% time series plot

figure(1)
subplot(2,1,1)
plot(timestamp, gageheight), datetick
ylabel('Gage Height (units?)')
title(gageno)

subplot(2,1,2)
plot(timestamp, discharge), datetick
ylabel('Discharge (units?)')

print('-dpng',['Timeseries_' gageno '.png'])

%% scatter plot

[year month day hour minute second] = datevec(timestamp);

figure(2), clf
scatter(gageheight, discharge, 10, year,'filled')
axis([0 inf 0 inf])
title(gageno)
ylabel('Discharge (units?)')
xlabel('Gage Height (units?)')
cbar = colorbar; cb.Label.String = 'year';

%% rating curve, taking the log of each side to enable a linear fit

gooddata = find( gageheight>0 & discharge>0);
offset = 0;

P = polyfit( log( gageheight(gooddata) - offset ), log(discharge(gooddata)), 1 );  % first order polynomial fit... y = mx + b

G = linspace(0,max(gageheight),10);
Q = exp(P(2)) .* (G - offset ).^P(1);

hold on % continue with previous figure
ratingcurve = plot(G,Q,'k','linewidth',2)

print('-dpng',['RatingCurve_' gageno '.png'])
