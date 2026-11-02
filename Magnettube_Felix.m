close all;
clear all;
clc;
s = serialport("COM5", 1500000, "Timeout", 3, "ByteOrder", "little-endian");
configureTerminator(s, "CR/LF");
pause(2);
flush(s);

%Alarmsound preparation
[audioData, Fs] = audioread('Alarmsound.mp3');
player = audioplayer(audioData,Fs);

%Counter = Amount of measurements for debugging purposes
counter=0;
% Grid for 2D quiver plot
[I, J] = ndgrid(1:8, 1:8);

% Grid for 3D quiver plot
[L, M, N] = ndgrid(1:8, 1:8, 1);

% Grid for surface plot
interpolating_factor = 5;
[Xg, Yg] = meshgrid(1:8);
[Xq, Yq] = meshgrid(1:1/interpolating_factor:8);

% Window Settings
screen_size = get(0, 'ScreenSize');
screen_height = screen_size(3);
screen_width = screen_size(2);

window_width = screen_height / 2;
window_height = screen_height / 2.22;
window_x_pos = 1000;
window_y_pos = 100;

fig = figure('Position', [window_x_pos window_y_pos window_width window_height]);

% Preparations for plots
% 2D quiver plot XY
subplot(2,3,1);
q1 = quiver(J, I, zeros(8), zeros(8));
axis equal tight
xlim([0.5, 8.5]);
ylim([0.5, 8.5]);
xlabel('y');
ylabel('x');
title('x - y');

% 3D quiver plot XYZ
subplot(2,3,2);
q4 = quiver3( ...
    M, L, N, ...
    zeros(8), zeros(8), zeros(8), ...
    'AutoScale', 'on', ...
    'AutoScaleFactor', 0.4, ...
    'LineWidth', 1 ...
);
xlim([0.5, 8.5]); ylim([0.5, 8.5]); zlim([0.5, 1.5]);
xlabel('y');
ylabel('x');
zlabel('z');
camproj('perspective');
view(20, 60);
grid on
title('x - y - z');

% 2D surface plot XYZ
ax = subplot(2,3,3);
q6 = surf(Xg, Yg, zeros(8), 'EdgeColor', 'none');
hold on
axis auto
q61 = scatter3(0, 0, 0, 50, 'r', 'filled');
hold off
xlim([0.5, 8.5]); ylim([0.5, 8.5]); zlim([-0.5, 10000.5]);
xlabel('y');
ylabel('x');
zlabel('z');
shading interp;
view(2);
grid on
title('Absolute Strength');

% 3D surface plot XY
subplot(2,3,4);
q5 = surf(Xg, Yg, zeros(8), 'EdgeColor', 'none');
hold on
axis auto
q51 = scatter3(0, 0, 0, 50, 'r', 'filled');
hold off
set(gca, 'zscale', 'log');
xlim([1, 8]); ylim([1, 8]); zlim([1e-1, 10000]);
xlabel('y');
ylabel('x');
zticks([0.1 1 10 100 1000]);
shading interp;
camproj('perspective');
view(20, 60);
grid on
title('Absolute Strength');


subplot(2,3,[5 6]);
img = imread('TracheaV2.jpeg');
img = rot90(img, 1);
imshow(img);

axis image
axis on
hold on

img_size = size(img);
xlim([0 img_size(2)])
ylim([0 img_size(1)])
set(gca, 'YDir','reverse');
title('Position des Tubus in der Trachea')


% Startposition im Tracheabild
startX = 753;
startY = 753;

%--- Kalibrierung und Mapping Vorbereitungen--- 
%Startposition vorerst
calibrated = false;
maxX_ref = 0;
maxY_ref = 0;

imageCenterX = startX;
imageCenterY = startY;

scale_x = 60;
scale_y = 60;

px_plot = startX;
py_plot = startY;
% Punkt für Magnetmaximum im Tracheaplot px und py getauscht für Korrekte
% darstellung
h_point = plot(px_plot, py_plot, 'o', 'MarkerSize', 8, 'LineWidth', 2, 'MarkerEdgeColor', 'k', 'MarkerFaceColor', 'k');
% Vorbereitungen für Tracheamaximumpunkte speichern (Nachleuchten)
traillength = 10;
trailPx = nan(1, traillength);
trailPy = nan(1, traillength);
h_trail = scatter(nan, nan, 20, 'k', 'filled');

% Alarm-Kreis 
theta = linspace(0,2*pi,50);
r = 160; % Erlaubter Radius in Pixeln
h_circle = fill( ...
    px_plot + r*cos(theta), ...
    py_plot + r*sin(theta), ...
    [1 0 1], ... % grün
    'FaceAlpha',0.5, ...
    'EdgeColor','none');



b1 = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Magnetic Reset');
b1.Position = [window_width/2-430 10 200 25];
b2 = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Zero');
b2.Position = [window_width/2-210 10 200 25];
b3 = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Magnetic Reset & Zero');
b3.Position = [window_width/2+10 10 200 25];
b4 = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Set Correlation Point');
b4.Position = [window_width/2+230 10 200 25];
b5 = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Persistence');
b5.Position = [window_width/2+450 10 160 25];

% --- Initialisierung Gerät ---
writeline(s, "format bin");
ack = readline(s);
disp("ACK format bin: " + strtrim(ack));

writeline(s, "averaging 8");
ack = readline(s);
disp("ACK averaging 8: " + strtrim(ack));

flush(s);

% Get reference
writeline(s, "measurement auto");
while s.NumBytesAvailable < 1024
    pause(0.1);
end

data = read(s, 256, "single");  % 64 Sensoren * 4 Werte = 256 singles
data_matrix = reshape(data, 4, 64);

ack = readline(s);
disp("ACK measurement auto: " + strtrim(ack));
if ~strcmp(strtrim(ack), "Done")
    error("Protocol error after measurement auto. ACK = '%s'", strtrim(ack));
end

vx_ref = data_matrix(1, :);
vy_ref = data_matrix(2, :);
vz_ref = data_matrix(3, :);

%c_point = zeros(8); Kann raus?
freq = zeros(50,1);
also_zero = false;

while(1)
    tic;


    if (b1.Value == true || b3.Value == true) % Magnetic Reset
        if (b3.Value == true)
            also_zero = true;
        end

        writeline(s, "reset");
        ack = readline(s);
        disp("ACK reset: " + strtrim(ack));

        if strcmp(strtrim(ack), "Done")
            fprintf("Magnetic reset successful\n");
        else
            fprintf("Error during magnetic reset: %s\n", strtrim(ack));
            break;
        end

        flush(s);

        if (b1.Value == true)
            b1.Value = false;
        end
    end


% Daten anfordern
writeline(s, "measurement read 0-63");

expectedBytes = 256 * 4;  % 256 single-Werte mit je 4 Bytes
timeout = 3;              % Sekunden
timedOut = false;         % timedOut flag   
t_receive = tic;

%Daten einlesen
while s.NumBytesAvailable < 1024
    if toc(t_receive) >= timeout
        fprintf("\n--- Empfangsdiagnose ---\n");
        fprintf("Zeit: %.3f s\n", toc(t_receive));
        fprintf("Bytes im Puffer: %d\n", s.NumBytesAvailable);

        % Bereits vorhandene Bytes sichern
        n = s.NumBytesAvailable;
        if n > 0
            raw = read(s, n, "uint8");
            fprintf("Erste Bytes (hex): ");
            fprintf("%02X ", raw(1:min(20, numel(raw))));
            fprintf("\n");
        end

        warning("Messdaten unvollständig empfangen.");
        %Reset ausführen
        writeline(s, "reset");
        ack = readline(s);
        disp("ACK reset: " + strtrim(ack));

        if strcmp(strtrim(ack), "Done")
            fprintf("Magnetic reset successful\n");
        else
            fprintf("Error during magnetic reset: %s\n", strtrim(ack));
            break;
        end
        flush(s);
        timedOut = true;
        break;
    end

    pause(0.05);
end

if timedOut
    continue;
end
bytesBeforeRead = s.NumBytesAvailable;
fprintf("Bytes vor dem Lesen: %d\n", bytesBeforeRead);

% Genau 256 single-Werte einlesen
data = read(s, 256, "single");

fprintf("Messwerte eingelesen: %d\n", numel(data));

% Abschlussbestätigung lesen
ack = strtrim(readline(s));
disp("ACK measurement read: " + ack);

if ~strcmp(ack, "Done")
    error("Protocol error after measurement read. ACK = '%s'", ack);
end

% Nächste Messung starten
writeline(s, "measurement start 0-63");
ack = strtrim(readline(s));
disp("ACK measurement start: " + ack);

if ~strcmp(ack, "Done")
    error("Protocol error after measurement start. ACK = '%s'", ack);
end

    % Daten umformatieren
    data_matrix = reshape(data, 4, 64);

    if (b2.Value == true || also_zero == true) % Zero
        vx_ref = data_matrix(1, :);
        vy_ref = data_matrix(2, :);
        vz_ref = data_matrix(3, :);

        if (b2.Value == true)
            b2.Value = false;
        end
        if (also_zero == true)
            b3.Value = false;
            also_zero = false;
        end
    end

    vx = data_matrix(1, :) - vx_ref;
    vy = data_matrix(2, :) - vy_ref;
    vz = data_matrix(3, :) - vz_ref;

    % In 8×8 Matrizen umformen
    X = fliplr(reshape(vx, 8, 8)).';
    Y = fliplr(reshape(vy, 8, 8)).';
    Z = fliplr(reshape(-vz, 8, 8)).';

    % Betrag errechnen
    V = sqrt(X.^2 + Y.^2 + Z.^2);
    Vq = interp2(Xg, Yg, V, Xq, Yq, 'cubic');

    %Kallibrierungsbutton gedrückt
    if (b4.Value == true)
        maxX_ref = maxX;
        maxY_ref = maxY;
        calibrated = true;
    
        b4.Value = false;
    end

    % Maximum
    [maxValue, maxIndex] = max(Vq(:));
    [maxY, maxX] = ind2sub(size(Vq), maxIndex);
    maxX = maxX / interpolating_factor + (interpolating_factor - 1) / interpolating_factor;
    maxY = maxY / interpolating_factor + (interpolating_factor - 1) / interpolating_factor;
    
    %Mapping des Sensorgitters auf das Tracheabild
    if calibrated
        dx = maxX - maxX_ref;
        dy = maxY - maxY_ref;

        px_plot = imageCenterX + scale_x * dy;
        py_plot = imageCenterY - scale_y * dx;

    else
        px_plot = imageCenterX;
        py_plot = imageCenterY;
    end

  
    %Alarmsystemberechnung
    dist = sqrt((px_plot - imageCenterX)^2 +(py_plot - imageCenterY)^2);
    alarm = dist > r;

    % Vector data aktualisieren
    set(q1, 'UData', Y, 'VData', X);
    set(q4, 'UData', Y, 'VData', X, 'WData', Z);
    set(q5, 'XData', Xq, 'YData', Yq, 'ZData', Vq);
    set(q51, 'XData', maxX, 'YData', maxY, 'ZData', maxValue);
    set(q6, 'XData', Xq, 'YData', Yq, 'ZData', Vq);
    set(q61, 'XData', maxX, 'YData', maxY, 'ZData', maxValue);
    %aktualsiere Magnetmaximumpunkt im Plot
    set(h_point,'XData', px_plot, 'YData', py_plot);

    
if b5.Value == 1
    b5.String = 'Persistence: On';

    % Aktuelle Position zum Verlauf hinzufügen
    trailPx = [trailPx(2:end), px_plot];
    trailPy = [trailPy(2:end), py_plot];

    % Ältere Punkte kleiner, neueste Punkte größer
    pointSizes = linspace(5, 60, traillength);

    set(h_trail, ...
        'XData', trailPx, ...
        'YData', trailPy, ...
        'SizeData', pointSizes);

else
    b5.String = 'Persistence: Off';

    % Verlauf ausblenden und zurücksetzen
    set(h_trail, ...
        'XData', nan(1, traillength), ...
        'YData', nan(1, traillength), ...
        'SizeData', 20 * ones(1, traillength));

    trailPx = nan(1, traillength);
    trailPy = nan(1, traillength);
end

    
    drawnow limitrate;

    freq = circshift(freq, 1);
    freq(1) = 1 / toc;
    fprintf('Frequency: %f Hz\n', mean(freq));
    
    %Alarmsystem aktion
    if alarm
    
    %Circle color to red when alarm
    set(h_circle, 'FaceColor', 'r');
    % FOR DEBUGGING set(h_point, 'Color', 'r', 'MarkerSize', 15);
    % Nur starten wenn:
    % 1. Alarm gerade neu ist
    % 2. Kein Sound läuft
        if alarm && strcmp(player.Running, 'off')
            play(player);
        end


    else
    %Set circle to green when no alarm
    set(h_circle, 'FaceColor', [0 1 0]);
    end

end
