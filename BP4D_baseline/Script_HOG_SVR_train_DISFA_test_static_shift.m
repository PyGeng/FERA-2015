%% load shared definitions and AU data
clear
shared_defs;

num_test_folds = 5;

% Set up the hyperparameters to be validated
hyperparams.c = 10.^(-7:1:3);
hyperparams.p = 10.^(-2);

hyperparams.validate_params = {'c', 'p'};

% Set the training function
svr_train = @svr_train_linear_shift;
    
% Set the test function (the first output will be used for validation)
svr_test = @svr_test_linear_shift;

pca_loc = '../pca_generation/generic_face_rigid.mat';
all_recs_BP4D = cat(2, train_recs, devel_recs);
hog_data_dir_BP4D = hog_data_dir;

aus = [6,12,17];
%%
for a=1:numel(aus)
    
    predictions_all = [];
    test_labels_all = [];
    
    au = aus(a);

    rest_aus = setdiff(all_aus, au);        

    [train_recs, valid_BP4D_recs] = get_balanced_fold_intensity(BP4D_dir_int, all_recs_BP4D, au, 1/4);

    % load the training and testing data for the current fold
    [train_samples, train_labels, ~, valid_samples, valid_labels, vid_ids_devel, ~, ~, ~, ~, success_devel] = Prepare_HOG_AU_data_generic_intensity(train_recs, valid_BP4D_recs, au, BP4D_dir_int, hog_data_dir_BP4D, pca_loc);

    train_samples = sparse(train_samples);
    valid_samples = sparse(valid_samples);

    hyperparams.success = success_devel;
    hyperparams.valid_samples = valid_samples;
    hyperparams.valid_labels = valid_labels;
    hyperparams.vid_ids = vid_ids_devel;        

    %% Cross-validate here                
    [ best_params, ~ ] = validate_grid_search_no_par(svr_train, svr_test, false, train_samples, train_labels, valid_samples, valid_labels, hyperparams);
    model = svr_train(train_labels, train_samples, best_params);        
    
    clear 'train_samples'
    clear 'valid_samples'
    
    %% Now apply that model on DISFA
    for t = 1:num_test_folds

        %% Test on DISFA
        find_DISFA;        
        od = cd('../DISFA_baseline/training/');
        test_folds = get_test_folds(num_test_folds, users);
        test_users = test_folds{t};
        train_users = setdiff(users, test_users); 
        all_disfa = [1,2,4,5,6,9,12,15,17,20,25,26];
        rest_aus = setdiff(all_disfa, au);    
        [~, ~, test_samples_disfa, test_labels_disfa,~,~,~,~, test_ids, test_success] = Prepare_HOG_AU_data_generic({}, test_users, au, rest_aus, hog_data_dir);
        % need to split the rest
        [~, ~, valid_samples_disfa, valid_labels_disfa, ~, PC, means, scaling, valid_ids, valid_success] = Prepare_HOG_AU_data_generic({}, train_users, au, rest_aus, hog_data_dir);
        cd(od);
        
        %% Learn shift                     
        prediction_DISFA_valid = valid_samples_disfa * model.w(1:end-1)' + model.w(end);
        
        % learn to shift
        cutoffs = 0:0.05:0.8;
        results = zeros(numel(cutoffs)+1, 1);

        prediction_DISFA_valid(~valid_success) = 0;
    
        for c=1:numel(cutoffs)
            % perform shifting here per person
            users = unique(valid_ids);
        
            prediction_curr = prediction_DISFA_valid;

            for i=1:numel(users)

                preds_user = prediction_curr(strcmp(valid_ids, users(i)));
                sorted = sort(preds_user);

                % alternative, move to histograms and pick the highest one

                shift = sorted(round(end*cutoffs(c))+1);

                prediction_curr(strcmp(valid_ids, users(i))) = preds_user - shift;

            end
        
            prediction_curr(prediction_curr<0)=0;
            prediction_curr(prediction_curr>5)=5;

            [ ~, ~, ~, ccc, ~, ~ ] = evaluate_classification_results( prediction_curr, valid_labels_disfa );     
            result = ccc;
            results(c) = result;
        end
    
        % option of no cutoff as well
        cutoffs = cat(2,cutoffs, -1);
        prediction_DISFA_valid(prediction_DISFA_valid<0)=0;
        prediction_DISFA_valid(prediction_DISFA_valid>5)=5;
        [ ~, ~, ~, ccc, ~, ~ ] = evaluate_classification_results( prediction_DISFA_valid, valid_labels_disfa );     
    
        results(end) = ccc;

        [best, best_id] = max(results);
        result = results(best_id);
        model.cutoff = cutoffs(best_id);
        %% Actual prediction
        predictions_DISFA_test = test_samples_disfa * model.w(1:end-1)' + model.w(end);
        predictions_DISFA_test(~test_success) = 0;
        
        % do the shifting
        if(model.cutoff >= 0)
            % perform shifting here per person
            users = unique(test_ids);

            for i=1:numel(users)

                preds_user = predictions_DISFA_test(strcmp(test_ids, users(i)));
                sorted = sort(preds_user);

                % alternative, move to histograms and pick the highest one

                shift = sorted(round(end*model.cutoff)+1);

                predictions_DISFA_test(strcmp(test_ids, users(i))) = preds_user - shift;

            end
        end        
        
        predictions_DISFA_test(predictions_DISFA_test < 0) = 0;
        predictions_DISFA_test(predictions_DISFA_test > 5) = 5;
        
        predictions_all = cat(1, predictions_all, predictions_DISFA_test);
        test_labels_all = cat(1, test_labels_all, test_labels_disfa);
        
    end

    name = sprintf('results_regression/AU_%d_static_shift.mat', au);

    [ accuracies, F1s, corrs, ccc, rms, classes ] = evaluate_classification_results( predictions_all, test_labels_all );
    
    save(name, 'model', 'F1s', 'corrs', 'accuracies', 'ccc', 'rms', 'predictions_all', 'test_labels_all');
        
end

