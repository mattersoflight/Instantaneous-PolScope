classdef Package < hgsetget 
    % Defines the abstract class Package from which every user-defined packages
    % will inherit. This class cannot be instantiated.
%
% Copyright (C) 2012 LCCB 
%
% This file is part of QFSM.
% 
% QFSM is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
% 
% QFSM is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% 
% You should have received a copy of the GNU General Public License
% along with QFSM.  If not, see <http://www.gnu.org/licenses/>.
% 
% 

    properties(SetAccess = protected)
        createTime_ % The time when object is created.
        owner_ % The MovieData object this package belongs to
        processes_ % Cell array containing all processes who will be used in this package 
    end

    properties
        notes_ % The notes users put down
        outputDirectory_ %The parent directory where results will be stored.
                         %Individual processes will save their results to
                         %sub-directories of this directory.
    end

    methods (Access = protected)
        function obj = Package(owner, outputDirectory,varargin)
            % Constructor of class Package
            
            if nargin > 0
                obj.owner_ = owner; 
                obj.outputDirectory_ = outputDirectory;
                
                nVarargin = numel(varargin);
                if nVarargin > 1 && mod(nVarargin,2)==0
                    for i=1 : 2 : nVarargin-1
                        obj.(varargin{i}) = varargin{i+1};
                    end
                end
            
                obj.processes_ = cell(1,length(obj.getProcessClassNames));
                obj.createTime_ = clock;
            end
        end
        
        function [processExceptions, processVisited] = checkDependencies(obj, ...
                procID,processExceptions,processVisited)
            % Check the dependencies and return processExceptions            
            processVisited(procID) = true;
            
            % Get the parent processes and remove empty optional processes
            parentIndex = obj.getParent(procID);
            if isempty(parentIndex), return;  end
            
            for parentID = parentIndex
                % Recursively call dependencies check for unvisited processes
                if ~isempty(obj.processes_{parentID}) && ~processVisited(parentID)
                    [processExceptions, processVisited] = ...
                        obj.checkDependencies(parentID, processExceptions,processVisited);
                end
            end
            
            % Check parent process validity and add exception if
            % 1 - parent process is empty
            % 2 - parent process has at least one exception
            % 3 - required parent proc is not run successfully
            isValidParent = @(x) ~isempty(obj.processes_{x}) && ...
                isempty(processExceptions{x}) && obj.processes_{x}.success_;
            invalidParent= ~arrayfun(isValidParent,parentIndex);
                
            if obj.processes_{procID}.success_ && ...
                    (any(invalidParent) || ~obj.processes_{procID}.updated_)
                % Set process's updated=false
                obj.processes_{procID}.setUpdated(false);
                % Create a dependency error exception
                statusMsg =['The step ' num2str(procID),': ' obj.processes_{procID}.getName...
                    ' is out of date. '];
                
                for parentID=parentIndex(invalidParent)
                    if obj.getDependencyMatrix(procID,parentID)==2 && ~obj.processes_{parentID}.success_
                        statusMsg = [statusMsg '\nbecause the optional step ' num2str(parentID),...
                            ': ', eval([obj.getProcessClassNames{parentID} '.getName']),...
                            ', changes the input data of current step.'];
                    else
                        statusMsg = [statusMsg '\nbecause the step ' num2str(parentID),': ',...
                            eval([obj.getProcessClassNames{parentID} '.getName']),...
                            ', which the current step depends on, is out of date.'];
                    end

                end
                statusMsg =  [statusMsg '\nPlease run again to update your result.'];
                ME = MException('lccb:depe:warn', statusMsg);

                % Add dependency exception to the ith process
                processExceptions{procID} = horzcat(processExceptions{procID}, ME);
            end
             
        end
        
    end
    methods
        
        function set.outputDirectory_(obj,value)
            if isequal(obj.outputDirectory_,value), return; end
            if ~isempty(obj.outputDirectory_), 
                stack = dbstack;
                if ~strcmp(stack(3).name,'MovieObject.relocate'),
                    error(['This channel''s ' propertyName ' has been set previously and cannot be changed!']);
                end
            end
            endingFilesepToken = [regexptranslate('escape',filesep) '$'];
            value = regexprep(value,endingFilesepToken,'');
            obj.outputDirectory_=value;
        end
        
        
        function [status processExceptions] = sanityCheck(obj, varargin)
            % sanityCheck is called by package's sanitycheck. It returns
            % a cell array of exceptions. Keep in mind, make sure all process
            % objects of processes checked in the GUI exist before running
            % package sanitycheck. Otherwise, it will cause a runtime error
            % which is not caused by algorithm itself.
            %
            % The following steps will be checked in this function
            %   I. The process itself has a problem
            %   II. The parameters in the process setting panel have changed
            %   III. The process that current process depends on has a
            %      problem
            %
            % OUTPUT:
            %   status - an array of boolean of size nProc. True if the
            %   process has been run successfully and has no exception.
            %
            %   processExceptions - a cell array with same length of
            % processes. It collects all the exceptions found in
            % sanity check. Exceptions of i th process will be saved in
            % processExceptions{i}
            %
            % INPUT:
            %   obj - package object
            %   full - true   check 1,2,3 steps
            %          false  check 2,3 steps
            %   procID - A. Numeric array: id of processes for sanitycheck
            %            B. String 'all': all processes will do
            %                                      sanity check
            %
            
            nProc = length(obj.getProcessClassNames);

            % Input check
            ip = inputParser;
            ip.CaseSensitive = false;
            ip.addRequired('obj');
            ip.addOptional('full',true, @(x) islogical(x));
            ip.addOptional('procID',1:nProc,@(x) (isvector(x) && ~any(x>nProc)) || strcmp(x,'all'));
            ip.parse(obj,varargin{:});
            full = ip.Results.full;
            procID = ip.Results.procID;
            if strcmp(procID,'all'), procID = 1:nProc;end
            
            % Allow dynamic package extension
            if nProc>numel(obj.processes_), 
                obj.processes_{numel(obj.processes_)+1:nProc}=deal([]); 
            end
            
            % Check processes are consistent with process class names
            assert(isequal(nProc,numel(obj.processes_)),'Wrong number of processes');
            validProc = procID(~cellfun(@isempty,obj.processes_(procID)));
            validClassCheck = arrayfun(@(x) isa(obj.processes_{x},obj.getProcessClassNames{x}),validProc);
            assert(all(validClassCheck),'Some processes do not agree with package classes definition');
            
            % Initialize process output
            status = false(1,nProc);
            processExceptions = cell(1,nProc);
            processVisited = false(1,nProc);
            
            if full 
                % I: Check if the process itself has a problem
                %
                % 1. Process sanity check
                % 2. Input directory  
                for i = validProc
                    try
                        obj.processes_{i}.sanityCheck;
                    catch ME
                        % Add process exception to the ith process
                        processExceptions{i} = horzcat(processExceptions{i}, ME);
                    end
                end
            end
            
            % II: Determine the parameters are changed if satisfying the
            % following two conditions:
            % A. Process has been successfully run (obj.success_ = true)
            % B. Pamameters are changed (reported by uicontrols in setting
            % panel, and obj.procChanged_ field is 'true')
            changedProc = validProc(cellfun(@(x) x.success_ && x.procChanged_,obj.processes_(validProc)));
            for i = changedProc                    
                % Add a changed parameter exception
                ME = MException('lccb:paraChanged:warn',['The step ' num2str(i),': ' obj.processes_{i}.getName...
                        ' is out of date because the parameters have been changed.']);
                processExceptions{i} = horzcat(processExceptions{i}, ME);
            end
                        
            % III: Check if the processes that current process depends
            % on have problems
            for i = validProc
                if ~processVisited(i)
                    [processExceptions, processVisited]= ...
                        obj.checkDependencies(i, processExceptions, processVisited);
                end
            end
            
            % Return array of boolean 
            saneProc = validProc(cellfun(@isempty,processExceptions(validProc)) &...
                cellfun(@(x) x.success_,obj.processes_(validProc)));
            status(saneProc)=true;
            
        end
        
        function createDefaultProcess(obj, i)
            % Create ith process using default constructor
            assert(isempty(obj.processes_{i}),'Process already exists');
            newprocess=obj.getDefaultProcessConstructors{i}(obj.owner_,obj.outputDirectory_);
            obj.owner_.addProcess(newprocess);
            obj.setProcess(i,newprocess);
            % Run sanityCheck to set process dependencies
            obj.sanityCheck(); 
        end
        
        function setProcess(obj, i, newProcess)
            % set the i th process of obj.processes_ to newprocess
            % If newProcess = [ ], clear the process in package process
            % list
            assert(i<=length(obj.getProcessClassNames),...
                'UserDefined Error: i exceeds obj.processes length');
            if isa(newProcess,obj.getProcessClassNames{i}) ||...
                    isempty(newProcess)      
                obj.processes_{i} = newProcess;
            else
                error('User-defined: input should be Process object or empty.')
            end
        end
        
        function parentID = getParent(obj,procID)
            % Returns the list of valid parents for a given process
            
            % By default, get the required parent processes as well as
            % all non-empty optional parent processes
            reqParentIndex = find(obj.getDependencyMatrix(procID,:)==1);
            optParentIndex = find(obj.getDependencyMatrix(procID,:)==2);
            isValidOptParent = ~cellfun(@isempty,obj.processes_(optParentIndex));
            validOptParentIndex = optParentIndex(isValidOptParent);
            parentID=sort([reqParentIndex,validOptParentIndex]);
        end
        
        function relocate(obj,oldRootDir,newRootDir)
            obj.outputDirectory_ = relocatePath(obj.outputDirectory_,oldRootDir,newRootDir);
        end
        
    end
        
    methods(Static)
        function tools = getTools()
            tools=[];
        end
        function class = getMovieClass()
            class = 'MovieData';
        end
    end 

    methods(Static,Abstract)
        GUI
        getName
        getDependencyMatrix
        getProcessClassNames
        getDefaultProcessConstructors
    end
    
end
