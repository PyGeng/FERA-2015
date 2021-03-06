function Script_HOG_SVM_train_joint_dynamic()

% Change to your downloaded location
addpath('C:\liblinear\matlab')
addpath('../data extraction/');
%% load shared definitions and AU data
shared_defs;
bp4d_au = intersect([1, 2, 4, 6, 7, 10, 12, 14, 15, 17, 23], all_aus);
disfa_au = intersect([1,2,4,5,6,9,12,15,17,20,25,26], all_aus);

% Set up the hyperparameters to be validated
hyperparams.c = 10.^(-6:1:3);
% hyperparams.e = 10.^(-6:1:-1);
hyperparams.e = 10.^(-3);

hyperparams.validate_params = {'c', 'e'};

% Set the training function
svm_train = @svm_train_linear;
    
% Set the test function (the first output will be used for validation)
svm_test = @svm_test_linear;

pca_loc = '../pca_generation/generic_face_rigid.mat';

%%
for a=1:numel(aus)
    
    if(ismember(aus(a), bp4d_au) || ismember(aus(a), disfa_au))
    
        au = aus(a);

        rest_aus = setdiff(all_aus, au);        

        find_SEMAINE;
        % load the training and testing data for the current fold
        [train_samples, train_labels, test_samples, test_labels, raw_valid, PC, means, scaling] = Prepare_HOG_AU_data_generic_dynamic(train_recs, devel_recs, au, rest_aus, SEMAINE_dir, hog_data_dir, pca_loc);

        valid_samples = test_samples;
        valid_labels = test_labels;
        
        if(ismember(aus(a), bp4d_au))
            od = cd('../BP4D_baseline/');
            find_BP4D;
            [train_samples_bp4d, train_labels_bp4d, valid_samples_bp4d, valid_labels_bp4d, ~, ~, ~, ~] = Prepare_HOG_AU_data_generic_dynamic(train_recs, devel_recs, au, BP4D_dir, hog_data_dir, pca_loc);
            cd(od);
            
            % TODO should valid be included?
            train_samples = cat(1, train_samples, train_samples_bp4d);
            train_labels = cat(1, train_labels, train_labels_bp4d);
            
            valid_samples = cat(1, valid_samples, valid_samples_bp4d);
            valid_labels = cat(1, valid_labels, valid_labels_bp4d);
            
        end
    
        if(ismember(aus(a), disfa_au))
            find_DISFA;
            od = cd('../DISFA_baseline/training/');
            all_disfa = [1,2,4,5,6,9,12,15,17,20,25,26];
            rest_aus = setdiff(all_disfa, au);    
            [train_samples_disfa, train_labels_disfa, valid_samples_disfa, valid_labels_disfa, ~, ~, ~, ~] = Prepare_HOG_AU_data_generic_dynamic(users, au, rest_aus, hog_data_dir);            
            cd(od);
            % Binarise the models            
            train_labels_disfa(train_labels_disfa < 1) = 0;
            train_labels_disfa(train_labels_disfa >= 1) = 1;
            
            valid_labels_disfa(valid_labels_disfa < 1) = 0;
            valid_labels_disfa(valid_labels_disfa >= 1) = 1;
            
            % TODO should valid be included?
            train_samples = cat(1, train_samples, train_samples_disfa);
            train_labels = cat(1, train_labels, train_labels_disfa);
            
            valid_samples = cat(1, valid_samples, valid_samples_disfa);
            valid_labels = cat(1, valid_labels, valid_labels_disfa);
        end
        
        train_samples = sparse(train_samples);
        valid_samples = sparse(valid_samples);
        test_samples = sparse(test_samples);
        %% Cross-validate here                
        [ best_params, ~ ] = validate_grid_search(svm_train, svm_test, false, train_samples, train_labels, valid_samples, valid_labels, hyperparams);

        model = svm_train(train_labels, train_samples, best_params);        

        [prediction, a, actual_vals] = predict(test_labels, test_samples, model);

        % Go from raw data to the prediction
        w = model.w(1:end-1)';
        b = model.w(end);

        svs = bsxfun(@times, PC, 1./scaling') * w;

        % Attempt own prediction
        preds_mine = bsxfun(@plus, raw_valid, -means) * svs + b;

        assert(norm(preds_mine - actual_vals) < 1e-8);

        name = sprintf('paper_res/AU_%d_dynamic_combined.dat', au);
        
        pos_lbl = model.Label(1);
        neg_lbl = model.Label(2);
        
        write_lin_dyn_svm(name, means, svs, b, pos_lbl, neg_lbl);

        name = sprintf('paper_res/AU_%d_dynamic_combined.mat', au);

        tp = sum(test_labels == 1 & prediction == 1);
        fp = sum(test_labels == 0 & prediction == 1);
        fn = sum(test_labels == 1 & prediction == 0);
        tn = sum(test_labels == 0 & prediction == 0);

        precision = tp/(tp+fp);
        recall = tp/(tp+fn);

        f1 = 2 * precision * recall / (precision + recall);    

        save(name, 'model', 'f1', 'precision', 'recall');
    end
end

end

function [model] = svm_train_linear(train_labels, train_samples, hyper)
    comm = sprintf('-s 1 -B 1 -e %f -c %f -q', hyper.e, hyper.c);
    model = train(train_labels, train_samples, comm);
end

function [result, prediction] = svm_test_linear(test_labels, test_samples, model)

    w = model.w(1:end-1)';
    b = model.w(end);

    % Attempt own prediction
    prediction = test_samples * w + b;
    l1_inds = prediction > 0;
    l2_inds = prediction <= 0;
    prediction(l1_inds) = model.Label(1);
    prediction(l2_inds) = model.Label(2);
 
    %[prediction, a, actual_vals] = predict(test_labels, test_samples, model);           
    
    tp = sum(test_labels == 1 & prediction == 1);
    fp = sum(test_labels == 0 & prediction == 1);
    fn = sum(test_labels == 1 & prediction == 0);
    tn = sum(test_labels == 0 & prediction == 0);

    precision = tp/(tp+fp);
    recall = tp/(tp+fn);

    f1 = 2 * precision * recall / (precision + recall);

%     result = corr(test_labels, prediction);
    fprintf('F1:%.3f\n', f1);
    if(isnan(f1))
        f1 = 0;
    end
    result = f1;
end
