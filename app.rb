require 'sinatra'
require 'pdf-reader'

enable :sessions
set :bind, '0.0.0.0'
set :port, 4567

# -------------------------------
# AGE GROUPS
# -------------------------------
AGE_GROUPS = {
  "Child (5-12)"  => 5..12,
  "Adult (18-60)" => 18..60,
  "Senior (60+)"  => 61..120
}

# -------------------------------
# IN-MEMORY STORAGE
# -------------------------------
PATIENTS = {}

# -------------------------------
# HOME / LOGIN
# -------------------------------
get '/' do
  erb :index
end

post '/login' do
  id  = params[:patient_id].to_s.strip
  age = params[:age].to_i

  if id.empty? || age <= 0
    redirect '/'
  end

  age_group = AGE_GROUPS.find { |_, range| range.include?(age) }&.first || "Unknown"

  PATIENTS[id] ||= {
    name:      params[:name].to_s.strip,
    age:       age,
    age_group: age_group,
    history:   []
  }

  session[:pid] = id
  redirect '/dashboard'
end

# -------------------------------
# DASHBOARD
# -------------------------------
get '/dashboard' do
  redirect '/' unless session[:pid]
  @patient = PATIENTS[session[:pid]]
  erb :dashboard
end

# -------------------------------
# PDF UPLOAD + RULE-BASED ANALYSIS
# -------------------------------
post '/upload' do
  redirect '/' unless session[:pid]

  file = params[:report][:tempfile]

  begin
    reader = PDF::Reader.new(file)
    text   = reader.pages.map(&:text).join("\n")
  rescue => e
    session[:error] = "Could not read PDF: #{e.message}"
    redirect '/dashboard'
  end

  # --- DATE EXTRACTION ---
  extracted_date =
    text[/Date\s+of\s+Examination\s*:\s*([0-9]{2}-[A-Za-z]{3}-[0-9]{4})/i, 1] ||
    text[/Date\s*:\s*([0-9]{2}-[A-Za-z]{3}-[0-9]{4})/i, 1]

  report_date = extracted_date || Time.now.strftime("%d-%b-%Y")

  # --- REPORT TYPE DETECTION ---
  report_type =
    if text =~ /hypertension/i
      :hypertension
    elsif text =~ /diabetes/i
      :diabetes
    elsif text =~ /cholesterol/i
      :cholesterol
    elsif text =~ /cardio|heart/i
      :cardio
    else
      :general
    end

  # --- PARAMETER EXTRACTION ---
  values = {
    "Systolic BP"  => "-",
    "Diastolic BP" => "-",
    "Pulse"        => "-",
    "Blood Sugar"  => "-",
    "Cholesterol"  => "-"
  }

  case report_type
  when :hypertension
    values["Systolic BP"]  = text[/Systolic\s+Blood\s+Pressure\s*[–\-]\s*(\d+)/i, 1] || "-"
    values["Diastolic BP"] = text[/Diastolic\s+Blood\s+Pressure\s*[–\-]\s*(\d+)/i, 1] || "-"
    values["Pulse"]        = text[/Pulse\s+Rate\s*:\s*(\d+)/i, 1] || "-"
  when :diabetes
    values["Blood Sugar"]  = text[/Blood\s+Sugar\s*[–\-]\s*(\d+)/i, 1] || "-"
  when :cholesterol
    values["Cholesterol"]  = text[/Cholesterol\s*[–\-]\s*(\d+)/i, 1] || "-"
  when :cardio
    values["Pulse"]        = text[/Pulse\s+Rate\s*:\s*(\d+)/i, 1] || "-"
    values["Systolic BP"]  = text[/Systolic\s+Blood\s+Pressure\s*[–\-]\s*(\d+)/i, 1] || "-"
    values["Diastolic BP"] = text[/Diastolic\s+Blood\s+Pressure\s*[–\-]\s*(\d+)/i, 1] || "-"
  end

  summary =
    case report_type
    when :hypertension then "Findings suggest Hypertension."
    when :diabetes     then "Findings suggest Diabetes."
    when :cholesterol  then "Findings suggest High Cholesterol."
    when :cardio       then "Findings suggest Cardiovascular risk."
    else                    "No specific disorder detected."
    end

  PATIENTS[session[:pid]][:history] << {
    date:    report_date,
    values:  values,
    summary: summary
  }

  redirect '/dashboard'
end

# -------------------------------
# LOGOUT
# -------------------------------
get '/logout' do
  session.clear
  redirect '/'
end

# -------------------------------
# VIEWS (inline ERB)
# -------------------------------
__END__

@@index
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>MediChrono</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: Arial, sans-serif;
      background: #eef2f6;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 20px;
    }
    .card {
      background: #fff;
      padding: 36px 32px;
      max-width: 420px;
      width: 100%;
      border-radius: 16px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.1);
    }
    h2 {
      text-align: center;
      margin-bottom: 24px;
      font-size: 1.5rem;
      color: #2c3e50;
    }
    label {
      display: block;
      font-size: 0.85rem;
      color: #555;
      margin-bottom: 4px;
      margin-top: 14px;
    }
    input {
      width: 100%;
      padding: 11px 14px;
      border: 1px solid #ccc;
      border-radius: 8px;
      font-size: 0.95rem;
    }
    input:focus {
      outline: none;
      border-color: #2c7a9e;
    }
    button {
      width: 100%;
      padding: 12px;
      margin-top: 22px;
      background: #2c3e50;
      color: #fff;
      border: none;
      border-radius: 8px;
      font-size: 1rem;
      cursor: pointer;
    }
    button:hover { background: #1a252f; }
    .note {
      text-align: center;
      font-size: 0.75rem;
      color: #aaa;
      margin-top: 14px;
    }
  </style>
</head>
<body>
  <div class="card">
    <h2>&#10082; MediChrono</h2>
    <form method="post" action="/login">
      <label for="name">Patient Name</label>
      <input id="name" name="name" placeholder="e.g. Aarav Mehta" required>

      <label for="patient_id">Patient ID</label>
      <input id="patient_id" name="patient_id" placeholder="e.g. P-1024" required>

      <label for="age">Age</label>
      <input id="age" name="age" type="number" min="1" max="120" placeholder="e.g. 45" required>

      <button type="submit">Access Portal</button>
    </form>
    <p class="note">Not a diagnostic tool. For record-keeping purposes only.</p>
  </div>
</body>
</html>

@@dashboard
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>MediChrono – Dashboard</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: Arial, sans-serif;
      background: #eef2f6;
      padding: 30px 20px;
    }
    .card {
      background: #fff;
      padding: 28px;
      max-width: 760px;
      margin: 0 auto;
      border-radius: 16px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.1);
    }
    h2 { color: #2c3e50; margin-bottom: 4px; }
    .meta { font-size: 0.9rem; color: #666; margin-bottom: 20px; }
    .upload-form {
      background: #f4f7fb;
      padding: 16px;
      border-radius: 10px;
      margin-bottom: 24px;
    }
    .upload-form input[type=file] {
      display: block;
      margin-bottom: 10px;
      font-size: 0.9rem;
    }
    .upload-form button {
      padding: 9px 20px;
      background: #2c7a9e;
      color: #fff;
      border: none;
      border-radius: 7px;
      cursor: pointer;
      font-size: 0.9rem;
    }
    .upload-form button:hover { background: #1f5f7a; }
    h3 { color: #2c3e50; margin-bottom: 12px; }
    .report {
      background: #f7f9fc;
      border-left: 4px solid #2c7a9e;
      padding: 14px 16px;
      border-radius: 8px;
      margin-bottom: 14px;
    }
    .report strong { color: #2c3e50; }
    .report table {
      width: 100%;
      border-collapse: collapse;
      margin: 10px 0 8px;
      font-size: 0.9rem;
    }
    .report table td {
      padding: 4px 8px;
      border-bottom: 1px solid #e8ecf0;
    }
    .report table td:first-child { color: #555; width: 50%; }
    .report em { color: #777; font-size: 0.88rem; }
    .empty { color: #aaa; font-style: italic; padding: 20px 0; text-align: center; }
    .logout {
      display: inline-block;
      margin-top: 22px;
      color: #e74c3c;
      text-decoration: none;
      font-size: 0.9rem;
    }
    .logout:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <div class="card">
    <h2><%= @patient[:name] %></h2>
    <p class="meta">Age: <%= @patient[:age] %> &nbsp;|&nbsp; Group: <%= @patient[:age_group] %></p>

    <div class="upload-form">
      <form action="/upload" method="post" enctype="multipart/form-data">
        <input type="file" name="report" accept="application/pdf" required>
        <button type="submit">Upload &amp; Analyze Report</button>
      </form>
    </div>

    <h3>Medical History</h3>

    <% if @patient[:history].empty? %>
      <p class="empty">No reports uploaded yet.</p>
    <% else %>
      <% @patient[:history].reverse.each do |r| %>
        <div class="report">
          <strong>Date:</strong> <%= r[:date] %>
          <table>
            <% r[:values].each do |param, val| %>
              <tr><td><%= param %></td><td><%= val %></td></tr>
            <% end %>
          </table>
          <em><%= r[:summary] %></em>
        </div>
      <% end %>
    <% end %>

    <a href="/logout" class="logout">Logout</a>
  </div>
</body>
</html>
