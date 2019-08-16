classdef ShiftDrive < audioPlugin
   properties  
       
        phase = 0; % [0 - 2.5] 
        
        drive = 1; % [1 - 5]
        
        cleanGain = 1; % [0 - 1]
        ipGain = 1; % [1 - 4]
        d1Gain = 0; % [0 - 1]
        d2Gain = 0; % [0 - 1] 
        d3Gain = 0; % [0 - 1] 
        fwrGain = 0; % [0 - 1]
        tcGain = 0; % [0 - 1]
        level = 1; % [0 - 1.4]
        
   end
   properties (Dependent)
        % Feedback gain for each clipper
        FeedbackLevel = 0;
    end
    properties (Constant)                           
        PluginInterface = audioPluginInterface(...
            'PluginName','Shift Drive',...
            'VendorName','Sean Newell',...
            'VendorVersion','1.0.0',...
            audioPluginParameter('phase',...         
            'DisplayName','Phase',...           
            'Mapping',{'lin',0,2.5}),...
            audioPluginParameter('FeedbackLevel',...
            'DisplayName','Feedback',...
            'Mapping',{'lin', 0,.7}),...
            audioPluginParameter('drive',...         
            'DisplayName','Drive',...           
            'Mapping',{'lin',1,5}),...
            audioPluginParameter('cleanGain',...         
            'DisplayName','clean',...           
            'Mapping',{'lin',0,1}),...
            audioPluginParameter('d1Gain',...         
            'DisplayName','d1',...           
            'Mapping',{'lin',0,1}),...
            audioPluginParameter('d2Gain',...         
            'DisplayName','d2',...           
            'Mapping',{'lin',0,1}),...
            audioPluginParameter('d3Gain',...         
            'DisplayName','d3',...           
            'Mapping',{'lin',0,1}),...
            audioPluginParameter('tcGain',...         
            'DisplayName','tc',...           
            'Mapping',{'lin',0,1}),...
            audioPluginParameter('fwrGain',...         
            'DisplayName','fwr',...           
            'Mapping',{'lin',0,1}),...
            audioPluginParameter('level',...         
            'DisplayName','Level',...           
            'Mapping',{'lin',0,1.4}));
    end 
    
    properties (Access = private)        
        % DelayFilter objects for fractional delay
        pFractionalDelay1
        pFractionalDelay2
        pFractionalDelay3
        pFractionalDelay4
        pFractionalDelay5
        
        % pSR Sample rate
        pSR
        
        % Variables for the transistor clipper algorithm
        tcThresh = 0.06;
        tcRate = 0.00002; % the rate at which the threshold changes
        originalThresh = 0.06; 
    end
    
    methods
        function obj = ShiftDrive()
            fs = getSampleRate(obj);
            obj.pFractionalDelay1 = audioexample.DelayFilter( ...
                'SampleRate', fs);
            obj.pFractionalDelay2 = audioexample.DelayFilter( ...
                'SampleRate', fs);
            obj.pFractionalDelay3 = audioexample.DelayFilter( ...
                'SampleRate', fs);
            obj.pFractionalDelay4 = audioexample.DelayFilter( ...
                'SampleRate', fs);
            obj.pFractionalDelay5 = audioexample.DelayFilter( ...
                'SampleRate', fs);
            obj.pSR = fs;
        end
        
        function set.FeedbackLevel(obj, val)
            obj.pFractionalDelay1.FeedbackLevel = val;
            obj.pFractionalDelay2.FeedbackLevel = val;
            obj.pFractionalDelay3.FeedbackLevel = val;
            obj.pFractionalDelay4.FeedbackLevel = val;
            obj.pFractionalDelay5.FeedbackLevel = val;
        end
        
        function val = get.FeedbackLevel(obj)
            val = obj.pFractionalDelay1.FeedbackLevel;
        end
        
        function reset(obj)
            % Reset sample rate
            fs = getSampleRate(obj);
            obj.pSR = fs;
            
            % Reset delay
            obj.pFractionalDelay1.SampleRate = fs;
            obj.pFractionalDelay2.SampleRate = fs;
            obj.pFractionalDelay3.SampleRate = fs;
            obj.pFractionalDelay4.SampleRate = fs;
            obj.pFractionalDelay5.SampleRate = fs;
            reset(obj.pFractionalDelay1);
            reset(obj.pFractionalDelay2);
            reset(obj.pFractionalDelay3);
            reset(obj.pFractionalDelay4);
            reset(obj.pFractionalDelay5);
        end
        
        function out = process(obj, in)
            
            % Change phase relationship between each clipper
            phaseN = obj.phase / 10000;
            delayInSamples1 = phaseN * obj.pSR;
            if delayInSamples1 == 0
                delayInSamples2 = 0;
                delayInSamples3 = 0;
                delayInSamples4 = 0;
                delayInSamples5 = 0;
            else
                delayInSamples2 = (phaseN * 1.5) * obj.pSR;
                delayInSamples3 = (phaseN * 0.9) * obj.pSR;
                delayInSamples4 = (phaseN * 1.7) * obj.pSR;
                delayInSamples5 = (phaseN * 1.2) * obj.pSR;
            end
            
            % Generate distortion1 
            d1 = 0.3*atan(5*in * obj.drive);
                
            % Generate distortion2
            % http://www.willpirkle.com/forum/algorithm-design/chebyshev-waveshaping/
            d2 = .3 * (tanh(in * 5 * obj.drive) / tanh(6 * obj.drive)); 
                
            % Generate distortion3
            d3 = 0.8*(in -3 * obj.drive*(.33*in.^3 - .25*in.^4));
             
            % Get the updated input values to run
            % fwr and tc algorithms
            fwr = obj.drive*in;
            tc = obj.drive*in;   

            % Sample by sample
            for i = 1:size(in,1)

                % Generate fwr clippng
                if in(i,:) >= 0
                     fwr(i,:) = fwr(i,:);
                else
                     fwr(i,:) = -1*fwr(i,:);
                end
                
                % Generate transistor clipping
                if tc(i,:) > obj.tcThresh
                     tc(i,:) = obj.tcThresh;
                     % slightly decrease the thresh
                     obj.tcThresh = obj.tcThresh - obj.tcRate;
                elseif tc(i,:) < -obj.tcThresh
                     tc(i,:) = -obj.tcThresh;
                     % slightly decrease the thresh
                     obj.tcThresh = obj.tcThresh - obj.tcRate;       
                else
                     tc(i,:) = tc(i,:); 
                     % Reset the thesh
                     obj.tcThresh = obj.originalThresh;
                end
            end
            
            % Delay the distorted signals
            d1 = obj.pFractionalDelay1(delayInSamples1, d1);
            d2 = obj.pFractionalDelay2(delayInSamples2, d2);
            d3 = obj.pFractionalDelay3(delayInSamples3, d3);
            fwr = obj.pFractionalDelay4(delayInSamples4, fwr);
            tc = obj.pFractionalDelay5(delayInSamples5, tc);
            
            % Sum all of the clippers together
            out = obj.level*(obj.cleanGain*in + obj.d1Gain*d1...
                  + obj.d2Gain*d2 + obj.d3Gain*d3...
                  + obj.fwrGain*fwr + obj.tcGain*tc);            
        end
    end
end